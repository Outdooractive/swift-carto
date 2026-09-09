//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// A CartoCSS rule: a single property/value (or variable/value) combination,
/// like `polygon-opacity: 1.0;` or `@opacity: 1.0;`.
struct Rule {

    /// The property name, without any `instance/` prefix.
    var name: String
    /// The instance name for attachment-prefixed properties (`a/line-width`).
    var instance: String
    var value: Value
    /// Character index in the source file, for error messages.
    var index: Int
    var filename: String?
    /// Zoom bitmask carried over from the enclosing selector.
    var zoom: Int = Zoom.all
    var variable: Bool

    /// Unique id combining zoom/instance/name, used by the inheritance pass.
    var id: String {
        "\(zoom)#\(instance)#\(name)"
    }

    /// The symbolizer this property belongs to, from the mapnik reference
    /// (`line-width` → `line`); unknown properties map to themselves.
    var symbolizer: String {
        Reference.shared.symbolizer(forCSS: name) ?? name
    }

    init(name: String, value: Value, index: Int, filename: String?) {
        let parts = name.split(separator: "/").map(String.init)
        if parts.count > 1 {
            self.name = parts.last ?? name
            instance = parts.dropLast().joined(separator: "/")
        }
        else {
            self.name = name
            instance = "__default__"
        }
        self.value = value
        self.index = index
        self.filename = filename
        variable = name.hasPrefix("@")
    }

}

/// A comma-separated list of expressions: everything after the `:` in a rule.
struct Value {
    var values: [Node]
}

/// A parsed selector: elements (`#id`, `.class`, `Map`, `*`), filters,
/// zoom conditions, and an optional attachment name.
struct Selector {

    /// Elements in selector order. Only the head element is `#id`;
    /// descendants are all appended.
    var elements: [Element]
    var filters: FilterSet
    /// Evaluated zoom bitmask (after variable substitution).
    var zoom: Int
    /// Zoom conditions, evaluated at compile time (variables resolved).
    var zooms: [ZoomNode]
    var attachment: String?
    var conditions: Int
    var index: Int

    /// CSS-like specificity: `[id, class, conditions, position]`.
    var specificity: [Int] {
        var result = [0, 0, conditions, index]
        for element in elements {
            switch element.kind {
            case .id: result[0] += 1
            case .wildcard: break
            case .clazz: result[1] += 1
            }
        }
        return result
    }

}

struct Element: Equatable {

    enum Kind: Equatable {
        case id
        case clazz
        case wildcard
    }

    var value: String
    var kind: Kind
    var clean: String

    init(value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        self.value = trimmed
        if trimmed.hasPrefix("#") {
            kind = .id
            clean = String(trimmed.dropFirst())
        }
        else if trimmed.hasPrefix(".") {
            kind = .clazz
            clean = String(trimmed.dropFirst())
        }
        else {
            kind = .wildcard
            clean = trimmed
        }
    }

}

/// A flattened definition: a selector combined with its rules, ready for
/// inheritance and sorting. Mirrors carto's `tree.Definition`.
final class Definition {

    var elements: [Element]
    var rules: [Rule]
    var filters: FilterSet
    var zoom: Int
    var attachment: String
    var specificity: [Int]
    var index: Int
    var matchCount: Int = 0

    /// carto's `Definition.clone(filters)`: copies rules and ruleIndex.
    func clone(filters: FilterSet? = nil) -> Definition {
        let clone: Definition = .init(selector: Selector(
            elements: elements, filters: self.filters, zoom: zoom, zooms: [],
            attachment: attachment, conditions: 0, index: index), rules: rules)
        clone.filters = filters ?? self.filters
        clone.specificity = specificity
        clone.index = index
        clone.zoom = zoom
        clone.matchCount = matchCount
        return clone
    }

    init(selector: Selector, rules: [Rule]) {
        elements = selector.elements
        self.rules = rules
        filters = selector.filters
        zoom = selector.zoom
        attachment = selector.attachment ?? "__default__"
        specificity = selector.specificity
        index = selector.index

        if let first = selector.elements.first, first.value == "Map" {
            matchCount = 1
        }
    }

    /// carto's `Definition.addRules`: append rules that aren't the whole
    /// symbolizer default and whose id isn't present yet. Returns the number
    /// of rules added.
    @discardableResult
    func addRules(_ newRules: [Rule]) -> Int {
        var added = 0
        for rule in newRules {
            let isDefault = Reference.shared.selectorName(rule.name) == "default"
            if !isDefault, !rules.contains(where: { $0.id == rule.id }) {
                rules.append(rule)
                added += 1
            }
        }
        return added
    }

    /// Does this definition match a layer with `id`, the given classes, and
    /// a zoom bitmask? `zoom == nil` matches regardless (carto calls
    /// `appliesTo` without the zoom argument for layers without
    /// minzoom/maxzoom properties).
    func appliesTo(_ id: String, _ classes: Set<String>, _ zoom: Int?) -> Bool {
        if zoom == nil || (self.zoom & zoom!) > 0 {
            for element in elements {
                let matches: Bool = switch element.kind {
                case .wildcard:
                    true
                case .clazz:
                    classes.contains(element.clean)
                case .id:
                    id == element.clean
                }
                if !matches { return false }
            }
            matchCount += 1
            return true
        }
        return false
    }

}

/// A comment node (kept so that block comments can round-trip where needed).
struct CommentNode {
    var text: String
    var silent: Bool
}

/// A parsed but invalid chunk of input (carto's error recovery).
struct InvalidNode {
    var text: String
    var index: Int
}

/// The root of a parsed stylesheet.
struct MSSRoot {
    var nodes: [MSSNode]
}

enum MSSNode {
    case ruleset(RulesetNode)
    case rule(Rule)
    case comment(CommentNode)
    case invalid(InvalidNode)
}

/// A ruleset: one or more selectors and a block of content.
struct RulesetNode {
    var selectors: [Selector]
    var isMap: Bool
    var content: [MSSNode]
}
