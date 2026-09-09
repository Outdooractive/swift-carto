//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// One compiled symbolizer: a group of properties belonging to the same
/// symbolizer instance (carto's `symbolizers[key]` in
/// `symbolizersToObject`, keyed `instance/symbolizer`).
struct CompiledSymbolizer {
    /// Rule name → evaluated rule (insertion order preserved).
    var properties: [(String, Rule)]
}

/// A compiled rule: filters + zoom + symbolizers, ready for XML emission
/// (carto's `Definition.toObject` result).
struct CompiledRule {
    var filters: FilterSet
    var zoom: Int
    /// Ordered symbolizer key → properties.
    var symbolizers: [(String, [(String, Rule)])]
}

/// Compiles a set of definitions into rules for one layer: evaluates
/// values, splits on zoom, orders symbolizers.
struct RuleCompiler {

    var evaluator: Evaluator
    var messages: Messages

    init(evaluator: Evaluator) {
        self.evaluator = evaluator
        messages = evaluator.messages
    }

    /// carto's `Definition.toObject`: walk the definition's rules, splitting
    /// by zoom and collecting symbolizer property groups.
    ///
    /// Faithful port: `existing` maps filter-id → zoom mask still uncovered,
    /// shared across the definitions of one style. For each rule, a do-while
    /// re-collects symbolizers from that rule's position, intersecting the
    /// zoom down; each pass emits one rule for the uncovered zoom bits.
    mutating func compile(
        _ definition: Definition,
        existing: inout [String: Int]
    ) -> [CompiledRule] {
        var objects: [CompiledRule] = []
        let filterKey = definition.filters.idString
        if existing[filterKey] == nil { existing[filterKey] = Zoom.all }

        // Universal properties (symbolizer '*': image-filters, comp-op,
        // opacity, ...) are handled as Style attributes (carto's
        // StyleObject), so skip them here.
        let rules = definition.rules.filter {
            Reference.shared.symbolizer(forCSS: $0.name) != "*"
        }

        var i = 0
        while i < rules.count {
            var ruleZoom = rules[i].zoom
            // Skip rules whose zooms are already covered for this filter.
            if existing[filterKey]! & ruleZoom == 0 {
                i += 1
                continue
            }

            while true {
                var current = ruleZoom
                if current != 0 {
                    // collectSymbolizers(zooms, i)
                    var symbolizers: [String: [(String, Rule)]] = [:]
                    var j = i
                    while j < rules.count {
                        let child = rules[j]
                        let key = child.instance + "/" + child.symbolizer
                        let alreadyHas = symbolizers[key]?.contains { $0.0 == child.name } ?? false
                        if current & child.zoom != 0, !alreadyHas {
                            current &= child.zoom
                            symbolizers[key, default: []].append((child.name, child))
                        }
                        j += 1
                    }

                    if !symbolizers.isEmpty {
                        // zooms.rule &= (zooms.available &= ~zooms.current)
                        ruleZoom &= ~current
                        let emitZoom = existing[filterKey]! & current
                        if emitZoom != 0 {
                            // carto sorts symbolizers by the min rule index
                            // (character position) of their properties.
                            let sortedKeys = symbolizers.keys.sorted { lhs, rhs in
                                let lhsMin = symbolizers[lhs]!.map(\.1.index).min() ?? 0
                                let rhsMin = symbolizers[rhs]!.map(\.1.index).min() ?? 0
                                return lhsMin < rhsMin
                            }
                            var compiled: CompiledRule = .init(
                                filters: definition.filters, zoom: emitZoom, symbolizers: [])
                            for key in sortedKeys {
                                compiled.symbolizers.append((key, symbolizers[key]!))
                            }
                            objects.append(compiled)
                            existing[filterKey]! &= ~current
                        }
                    }
                }
                if current == 0 { break }
            }
            i += 1
        }

        return objects
    }

    // MARK: - Symbolizer serialization

    /// Serialize a compiled rule's symbolizers into XML nodes.
    mutating func symbolizersToXML(_ compiled: CompiledRule) -> XMLNode? {
        var ruleContent: [XMLNode] = []

        for (start, end) in Zoom.scaleDenominators(zoom: compiled.zoom) {
            ruleContent.append(.element(XMLNode.Element(name: start, content: end)))
        }

        if !compiled.filters.isEmpty {
            ruleContent.append(
                .element(
                    XMLNode.Element(
                        name: "Filter", children: [],
                        content: compiled.filters.toObject(&messages), cdata: true)))
        }

        var symCount = 0
        for (key, properties) in compiled.symbolizers {
            let symbolizerName = key.split(separator: "/").last.map(String.init) ?? key
            if symbolizerName == "*" { continue }
            symCount += 1

            if let failure = requiredFailure(symbolizer: symbolizerName, properties: properties) {
                let firstIndex = properties.first?.1.index
                messages.error(failure, filename: properties.first?.1.filename, index: firstIndex)
            }

            let symbolizer = Self.xmlName(symbolizerName)
            var attributes: [String: String] = [:]
            var content: String?
            var tagChildren: [XMLNode] = []
            var doNotSerialize = false

            let sorted = properties.sorted { $0.0 < $1.0 }
            for (name, rule) in sorted {
                if symbolizerName == "map" {
                    messages.error(
                        "Map properties are not permitted in other rules",
                        filename: rule.filename, index: rule.index)
                    continue
                }

                let reference: Reference = .shared
                guard let property = reference.property(name) else { continue }

                var evaluated = evaluator.evaluateValue(rule.value)
                // carto rounds 'unsigned' values at evaluation.
                if property.type == "unsigned", case let .dimension(d) = evaluated {
                    evaluated = .dimension(Dimension(value: d.value.rounded(), unit: d.unit))
                }
                let serialized = Self.serialize(evaluated, &messages, rule.filename, rule.index)

                if property.serialization == "content" {
                    content = serialized
                    continue
                }
                if property.serialization == "tag" {
                    // Tag serialization (raster-colorizer-stops): the value's
                    // entities become child elements.
                    tagChildren = Self.tagNodes(evaluated)
                    continue
                }

                // default-keyword handling
                if reference.selectorName(name) == "default" {
                    if case let .keyword(value) = evaluated {
                        if value == "none" {
                            doNotSerialize = true
                            continue
                        }
                        if value == "auto" {
                            continue
                        }
                    }
                }

                if case let .keyword(value) = evaluated, value == "none" {
                    doNotSerialize = true
                    continue
                }
                if case let .keyword(value) = evaluated, value == "auto" {
                    continue
                }

                if property.type == "font" {
                    // fontset handling: single font → face-name, list → fontset
                    let fontCount = Self.countFonts(evaluated)
                    if fontCount <= 1 {
                        attributes[property.xmlName] = serialized
                    }
                    else {
                        let fontSetName = fontSet(for: evaluated)
                        attributes["fontset-name"] = fontSetName
                    }
                    continue
                }

                attributes[property.xmlName] = serialized
            }

            if doNotSerialize { continue }

            var element = XMLNode.Element(name: symbolizer, attributes: attributes)
            if let content {
                element = XMLNode.Element(
                    name: symbolizer, attributes: attributes, children: [],
                    content: content, cdata: true)
            }
            if !tagChildren.isEmpty {
                element = XMLNode.Element(
                    name: symbolizer, attributes: attributes, children: tagChildren)
            }
            ruleContent.append(.element(element))
        }

        if symCount == 0 || ruleContent.isEmpty {
            return nil
        }
        return .element(XMLNode.element("Rule", content: ruleContent))
    }

    private func requiredFailure(symbolizer: String, properties: [(String, Rule)]) -> String? {
        let reference: Reference = .shared
        for (_, rule) in properties {
            if reference.selectorName(rule.name) == "default" {
                return nil
            }
        }
        for required in reference.requiredProperties(for: symbolizer) {
            if !properties.contains(where: { $0.0 == required }) {
                return "Property \(required) required for defining \(symbolizer) styles."
            }
        }
        return nil
    }

    static func countFonts(_ value: Node) -> Int {
        switch value {
        case let .expression(nodes):
            nodes.reduce(0) { $0 + countFonts($1) }
        case let .value(v):
            v.values.reduce(0) { $0 + countFonts($1) }
        case .keyword, .quoted:
            1
        default:
            1
        }
    }

    /// Create (or reuse) a font set for a list of fonts; returns its name.
    private mutating func fontSet(for value: Node) -> String {
        var fonts: [String] = []
        switch value {
        case let .value(v):
            for item in v.values {
                fonts.append(contentsOf: flattenFonts(item))
            }

        default:
            fonts.append(contentsOf: flattenFonts(value))
        }
        let key = fonts.joined()
        if let existing = evaluator.fontMap[key] {
            return existing
        }
        let name = "fontset-\(evaluator.fontSets.count)"
        evaluator.fontSets.append(FontSet(name: name, fonts: fonts))
        evaluator.fontMap[key] = name
        return name
    }

    private func flattenFonts(_ node: Node) -> [String] {
        switch node {
        case let .expression(nodes):
            nodes.flatMap { flattenFonts($0) }
        case let .value(value):
            value.values.flatMap { flattenFonts($0) }
        case let .quoted(s):
            // A quoted string containing commas splits into separate fonts
            // (carto's _flattenFontArray treats each list item as one font;
            // the quoted 'Arial, Helvetica Neue' stays one string — actually
            // carto keeps it whole). Keep whole.
            [s]
        case let .keyword(s):
            [s]
        default:
            [node.idString]
        }
    }

    // MARK: - Value serialization

    /// Serialize an evaluated node into its XML attribute string
    /// (carto's `Value.toString` chain).
    static func serialize(
        _ node: Node,
        _ messages: inout Messages,
        _ filename: String?,
        _ index: Int
    ) -> String {
        switch node {
        case let .dimension(d):
            return formatNumber(d.value)

        case let .color(c):
            return c.serialized()

        case let .quoted(s):
            return Self.escapeXML(s)

        case let .keyword(s):
            return s

        case let .field(s):
            return "[\(s)]"

        case let .literal(s):
            return s

        case let .url(s):
            return s

        case .variable:
            return node.idString

        case let .operation(op):
            return Node.operation(op).idString

        case let .expression(nodes):
            return nodes.map { serialize($0, &messages, filename, index) }.joined(separator: " ")

        case let .value(v):
            return v.values.map { serialize($0, &messages, filename, index) }.joined(separator: ", ")

        case let .call(call):
            return call.name + "(" + call.args.map { serialize($0, &messages, filename, index) }.joined(separator: ",") + ")"

        case .tag:
            return ""

        case let .imageFilter(name, args):
            if args.isEmpty {
                return name
            }
            return name + "(" + args.map { serialize($0, &messages, filename, index) }.joined(separator: ",") + ")"

        case .undefined:
            messages.error("undefined value in output", filename: filename, index: index)
            return "undefined"
        }
    }

    /// Child elements for tag-serialized values (carto's `stop` tags).
    static func tagNodes(_ node: Node) -> [XMLNode] {
        switch node {
        case let .expression(nodes):
            return nodes.flatMap { tagNodes($0) }

        case let .value(value):
            return value.values.flatMap { tagNodes($0) }

        case let .tag(tag):
            var attributes: [String: String] = [:]
            for (name, attributeValue) in tag.attributes {
                attributes[name] = attributeValue
            }
            return [.element(XMLNode.element(tag.name, attributes: attributes))]

        default:
            return []
        }
    }

    static func escapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
    }

    static func xmlName(_ symbolizer: String) -> String {
        let parts = symbolizer.split(separator: "-")
        let capitalized = parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return capitalized + "Symbolizer"
    }

}

extension Reference {

    func selectorName(_ css: String) -> String {
        // The 'default' pseudo-properties (`polygon`, `line`, ...) map to
        // xmlName 'default'.
        if let property = Self.propertiesByCSS[css] {
            return property.xmlName == "default" ? "default" : property.xmlName
        }
        return css
    }

}
