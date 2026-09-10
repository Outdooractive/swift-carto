//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// Compiles parsed stylesheets into definitions, applies inheritance,
/// and emits per-layer styles. Ports carto's `renderer.js`
/// (`inheritDefinitions`, `sortStyles`, `foldStyle`) and the definition
/// compilation (`tree.Definition.toObject`).
struct Compiler {

    var messages: Messages
    var evaluator: Evaluator

    init(evaluator: Evaluator) {
        self.evaluator = evaluator
        messages = evaluator.messages
    }

    // MARK: - Flatten (parse tree → definitions)

    /// Flatten a stylesheet's parse tree into definitions.
    ///
    /// Mirrors carto's `Ruleset.flatten`: nested rulesets multiply their
    /// parent selectors, rules attach to the enclosing selectors, and
    /// variables are resolved from root frames plus enclosing ruleset
    /// variables.
    mutating func flatten(_ roots: [MSSRoot]) throws -> [Definition] {
        var definitions: [Definition] = []
        var frames: [[String: Rule]] = []

        for root in roots {
            var variables: [String: Rule] = [:]
            for node in root.nodes {
                if case let .rule(rule) = node, rule.variable {
                    variables[rule.name] = rule
                }
            }
            // Root frames are pushed in order (carto's env.frames for the
            // stylesheet chain).
            frames.append(variables)
        }

        evaluator.frames = frames

        for root in roots {
            // Rules at the root level and rulesets; variables already known.
            var rules: [Rule] = []
            var rulesets: [RulesetNode] = []
            for node in root.nodes {
                switch node {
                case let .rule(rule):
                    if !rule.variable {
                        rules.append(rule)
                    }

                case let .ruleset(ruleset):
                    rulesets.append(ruleset)

                case .comment, .invalid:
                    break
                }
            }

            if !rules.isEmpty {
                // carto: the root Ruleset has no selectors, so bare root
                // rules land in env.frames but produce no definitions.
                // Variables are available; plain root rules are ignored
                // (no selector to attach to).
                continue
            }

            for ruleset in rulesets {
                try flattenRuleset(
                    ruleset, parents: [], into: &definitions)
            }
        }

        definitions.sort(by: Self.specificitySort)
        return definitions
    }

    /// carto's `Ruleset.flatten` for one ruleset.
    private mutating func flattenRuleset(
        _ ruleset: RulesetNode,
        parents: [Selector],
        into result: inout [Definition],
    )
    throws {
        var selectors: [Selector] = []
        // carto's evZooms runs before the merge: evaluate this ruleset's own
        // zoom conditions first.
        var childSelectors = ruleset.selectors
        for index in childSelectors.indices {
            childSelectors[index].zoom = evaluateZooms(childSelectors[index])
        }
        for child in childSelectors {
            if parents.isEmpty {
                selectors.append(child)
                continue
            }
            for parent in parents {
                switch parent.filters.merging(child.filters) {
                case .conflict:
                    continue

                case .unchanged:
                    if parent.zoom & child.zoom == parent.zoom,
                       parent.attachment == child.attachment,
                       parent.elements == child.elements
                    {
                        selectors.append(parent)
                    }
                    else {
                        var clone = child
                        clone.filters = parent.filters
                        clone.zoom = parent.zoom & child.zoom
                        clone.elements = parent.elements + child.elements
                        clone.attachment = mergeAttachment(parent.attachment, child.attachment)
                        clone.conditions = parent.conditions + child.conditions
                        selectors.append(clone)
                    }

                case let .merged(merged):
                    var clone = child
                    clone.filters = merged
                    clone.zoom = parent.zoom & child.zoom
                    clone.elements = parent.elements + child.elements
                    clone.attachment = mergeAttachment(parent.attachment, child.attachment)
                    clone.conditions = parent.conditions + child.conditions
                    selectors.append(clone)
                }
            }
        }

        var rules: [Rule] = []
        var nestedRulesets: [RulesetNode] = []
        var localVariables: [String: Rule] = [:]
        for node in ruleset.content {
            switch node {
            case let .rule(rule):
                if rule.variable {
                    localVariables[rule.name] = rule
                }
                else {
                    rules.append(rule)
                }

            case let .ruleset(nested):
                nestedRulesets.append(nested)

            case .comment, .invalid:
                break
            }
        }

        // Local variables are visible while evaluating this level's rules.
        evaluator.pushFrame(localVariables)

        var evaluatedRules: [Rule] = []
        for var rule in rules {
            rule.zoom = selectors.first?.zoom ?? Zoom.all
            evaluatedRules.append(rule)
        }

        let firstIndex = evaluatedRules.first?.index
        for selector in selectors {
            var updated = selector
            if let firstIndex {
                updated.index = firstIndex
            }
            // Each definition stamps its own selector's zoom onto the rules
            // (carto's Definition constructor).
            var selectorRules = evaluatedRules
            for ruleIndex in selectorRules.indices {
                selectorRules[ruleIndex].zoom = selector.zoom
            }
            result.append(Definition(selector: updated, rules: selectorRules))
        }

        // Recurse into nested rulesets with these selectors as parents.
        for nested in nestedRulesets {
            try flattenRuleset(nested, parents: selectors, into: &result)
        }

        evaluator.popFrame()
    }

    private func mergeAttachment(
        _ parent: String?,
        _ child: String?,
    ) -> String? {
        if let parent, let child {
            return parent + "/" + child
        }
        return child ?? parent
    }

    /// Combine the zoom conditions of a selector into a bitmask, resolving
    /// variables (carto's `Ruleset.evZooms`).
    private mutating func evaluateZooms(_ selector: Selector) -> Int {
        var zoom = Zoom.all
        for condition in selector.zooms {
            let mask = Zoom.evaluate(
                op: condition.op,
                value: condition.value,
                evaluator: &evaluator,
                messages: &messages,
                index: condition.index,
                filename: evaluator.env.filename)
            zoom &= mask
        }
        return zoom
    }

    // MARK: - Sorting

    /// carto's `specificitySort`.
    static func specificitySort(_ a: Definition, _ b: Definition) -> Bool {
        let asx = a.specificity
        let bsx = b.specificity

        if asx[0] != bsx[0] {
            return asx[0] > bsx[0]
        }
        if asx[1] != bsx[1] {
            return asx[1] > bsx[1]
        }
        if asx[2] != bsx[2] {
            return asx[2] > bsx[2]
        }
        if bsx[3] != asx[3] {
            return bsx[3] < asx[3]
        }

        // The definition with the most elements is 'larger'
        if a.elements.count != b.elements.count {
            return a.elements.count > b.elements.count
        }

        // Sort based on the alphabetic order of each element. carto compares
        // Element *objects* here: at the first pair of distinct objects it
        // returns `localeCompare(a.value, b.value)` — 0 for equal values,
        // which makes the comparator "order undefined" (the stable sort
        // keeps flatten order). Only when the two definitions share the
        // same element *objects* (nested ruleset clones reuse the parent's
        // elements) does the loop continue to the zoom comparison.
        for (ae, be) in zip(a.elements, b.elements) {
            if ae.instanceID != be.instanceID {
                if ae.value != be.value {
                    return ae.value < be.value
                }
                return false
            }
        }

        if a.zoom != b.zoom {
            return a.zoom > b.zoom
        }

        return false
    }

    // MARK: - Inheritance

    /// carto's `inheritDefinitions`: fold later same-attachment definitions
    /// into earlier ones, splitting on filters. `byFilter` (per attachment)
    /// reuses merged-filter clones across the whole pass.
    mutating func inherit(_ definitions: [Definition]) -> [[Definition]] {
        var byAttachment: [String: Int] = [:]
        var byFilter: [String: [String: Definition]] = [:]
        var result: [[Definition]] = []

        // Evaluate filter values (variable substitution etc.) first, like
        // carto's `d.filters.ev(env)` in inheritDefinitions.
        for definition in definitions {
            definition.filters = evaluateFilters(definition.filters)
        }

        for i in definitions.indices {
            let attachment = definitions[i].attachment
            var current = [definitions[i]]

            if byAttachment[attachment] == nil {
                byAttachment[attachment] = result.count
                result.append([])
                byFilter[attachment] = [:]
            }

            for j in (i + 1) ..< definitions.count where definitions[j].attachment == attachment {
                current = Self.addRules(current, definitions[j], byFilter: &byFilter[attachment]!)
            }

            for definition in current {
                byFilter[attachment]![definition.filters.idString] = definition
                result[byAttachment[attachment]!].append(definition)
            }
        }

        return result
    }

    /// carto's `Filterset.ev`: evaluate every filter's key/value nodes and
    /// rebuild the set (add() dedupes/canonicalizes).
    mutating func evaluateFilters(_ set: FilterSet) -> FilterSet {
        var result: FilterSet = .init()
        for filter in set.allFilters {
            let key = evaluator.evaluate(filter.key)
            let value = evaluator.evaluate(filter.value)
            var updated = filter
            updated.key = key
            updated.value = value
            if let error = result.add(updated) {
                messages.error(error, filename: filter.filename, index: filter.index)
            }
        }
        return result
    }

    /// carto's `addRules`: merge a definition's rules into a running list,
    /// splitting definitions whose filters intersect. `byFilter` maps
    /// filter-id → definition for clone reuse.
    static func addRules(
        _ current: [Definition], _ definition: Definition, byFilter: inout [String: Definition],
    ) -> [Definition] {
        var result = current
        var k = 0
        while k < result.count {
            switch result[k].filters.merging(definition.filters) {
            case .conflict:
                // Filters split the inheritance chain: skip.
                break

            case .unchanged:
                // Adding the filters doesn't change anything: clone the
                // definition (it may already be pushed) and add the rules.
                let clone = result[k].clone()
                _ = clone.addRules(definition.rules)
                result[k] = clone

            case let .merged(mergedFilters):
                let mergedId = mergedFilters.idString
                if let previous = byFilter[mergedId] {
                    // A definition with those exact filters already exists:
                    // add the rules there (mutated in place, like carto).
                    _ = previous.addRules(definition.rules)
                }
                else {
                    let clone = result[k].clone(filters: mergedFilters)
                    if clone.addRules(definition.rules) > 0 {
                        byFilter[mergedId] = clone
                        result.insert(clone, at: k)
                        // carto's k++: skip the freshly inserted clone.
                        k += 1
                    }
                }
            }
            k += 1
        }
        return result
    }

    // MARK: - Style sorting

    /// carto's `sortStyles`: sort attachment groups by their minimum rule
    /// index, descending.
    static func sortStyles(_ styles: [[Definition]]) -> [[Definition]] {
        var indexed: [([Definition], Int)] = []
        for style in styles {
            var index: Int = .max
            for definition in style {
                for rule in definition.rules {
                    index = min(index, rule.index)
                }
            }
            indexed.append((style, index == Int.max ? Int.max : index))
        }
        // sortStylesIndex: b.index - a.index (descending)
        return indexed.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// carto's `foldStyle`: remove definitions that can never be reached
    /// under `filter-mode: first`. The style must be sorted. `j` is removed
    /// when `j`'s filters are a subset of `i`'s (carto:
    /// `style[j].filters.cloneWith(style[i].filters) === null`).
    static func foldStyle(_ style: [Definition]) -> [Definition] {
        var style = style
        for i in style.indices {
            var j = style.count - 1
            while j > i {
                if case .unchanged = style[j].filters.merging(style[i].filters) {
                    style.remove(at: j)
                }
                j -= 1
            }
        }
        return style
    }

}
