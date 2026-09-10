//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// The CartoCSS compiler: loads an MML project, parses its stylesheets,
/// and renders Mapnik XML — a Swift port of Mapbox's archived `carto`.
public struct Renderer {

    /// Compile messages (errors/warnings) from the last render.
    public private(set) var messages: [Message] = []

    /// The pixels-per-inch used to convert physical units (m, mm, cm, in,
    /// pt, pc) to pixels; carto's default is 90.714.
    private let ppi: Double

    /// - Parameter ppi: Pixels per inch for unit conversion; carto's
    ///   default (and the CLI default) is 90.714.
    public init(ppi: Double = 90.714) {
        self.ppi = ppi
        Reference.loadProperties()
    }

    /// Render an MML document (loaded stylesheets) to Mapnik XML.
    /// Returns `nil` when compilation produced errors (messages carry the
    /// details).
    public mutating func render(_ mml: MML) -> String? {
        var localMessages: Messages = .init()

        var evaluator: Evaluator = .init(env: ParserEnv(ppi: ppi), messages: localMessages)
        var compiler = Compiler(evaluator: evaluator)

        // Parse every stylesheet; definitions are collected across
        // stylesheets, variables shared (carto passes env between them).
        var roots: [MSSRoot] = []
        for stylesheet in mml.stylesheets {
            var env: ParserEnv = .init(ppi: ppi, filename: stylesheet.id)
            env.inputs[stylesheet.id] = stylesheet.data
            evaluator.env.filename = stylesheet.id
            do {
                let root = try MSSParser.parse(stylesheet.data, env: env)
                roots.append(root)
            }
            catch {
                localMessages.error("\(error)", filename: stylesheet.id)
                messages = localMessages.items
                return nil
            }
        }

        // Flatten to definitions
        var definitions: [Definition] = []
        do {
            definitions = try compiler.flatten(roots)
            evaluator = compiler.evaluator
        }
        catch {
            localMessages.error("\(error)")
            messages = localMessages.items
            return nil
        }

        // Map-level properties from Map {} blocks + MML srs
        var mapAttributes: [String: String] = [:]
        if let srs = mml.srs {
            mapAttributes["srs"] = srs
        }
        for definition in definitions where definition.elements.first?.value == "Map" {
            for var rule in definition.rules {
                rule.zoom = Zoom.all
                // Evaluate
                let evaluated = evaluator.evaluateValue(rule.value)
                let reference: Reference = .shared
                guard let property = reference.property(rule.name) else {
                    localMessages.error(
                        "Unrecognized rule: \(rule.name).", filename: rule.filename, index: rule.index)
                    continue
                }

                mapAttributes[property.xmlName] = RuleCompiler.serialize(
                    evaluated, &localMessages, rule.filename, rule.index)
            }
        }

        var output: [XMLNode] = []

        // FontSets collected during evaluation come first.
        var fontSetNodes: [XMLNode] = []

        // Per-layer styles
        for layer in mml.layers {
            var styles: [String] = []
            let classes: Set = .init(layer.classes)

            // Definitions matching this layer. Layer-level minzoom/maxzoom
            // restrict the zoom range definitions must intersect (carto's
            // appliesTo zoom mask).
            var matching: [Definition] = []
            // carto only restricts by the layer's zoom range when the layer
            // has minzoom/maxzoom properties; otherwise appliesTo matches
            // every definition.
            var layerZoomMask: Int?
            var minZoom = 0
            var maxZoom = Zoom.maxZoom
            var minOrMaxZoom = false
            if let minzoom = layer.properties?.first(where: { $0.0 == "minzoom" })?.1.intValue,
               minzoom > 0
            {
                minZoom = minzoom
                minOrMaxZoom = true
            }
            if let maxzoom = layer.properties?.first(where: { $0.0 == "maxzoom" })?.1.intValue,
               maxzoom <= Zoom.maxZoom
            {
                maxZoom = maxzoom
                minOrMaxZoom = true
            }
            if minOrMaxZoom {
                layerZoomMask = Zoom.rangeMask(start: minZoom, end: maxZoom)
            }
            for definition in definitions {
                if definition.elements.first?.value == "Map" {
                    continue
                }
                definition.matchCount = 0
                if definition.appliesTo(layer.id, classes, layerZoomMask) {
                    matching.append(definition)
                }
            }

            if matching.isEmpty {
                localMessages.warning("Layer \(layer.id) has no styles associated with it.")
            }

            // Inheritance per attachment
            var compiler = Compiler(evaluator: evaluator)
            let inherited = compiler.inherit(matching)
            evaluator = compiler.evaluator
            let sorted = Compiler.sortStyles(inherited)

            for var style in sorted {
                style = Compiler.foldStyle(style)
                let attachment = style.first?.attachment ?? "__default__"
                let styleName =
                    attachment == "__default__" ? layer.id : layer.id + "-" + attachment

                var ruleCompiler = RuleCompiler(evaluator: evaluator)
                // carto's StyleObject: the `existing` map (filter → uncovered
                // zooms) is shared across the definitions of one style.
                var existing: [String: Int] = [:]
                var styleContent: [XMLNode] = []
                var styleAttributes: [String: String] = [:]
                styleAttributes["filter-mode"] = "first"
                styleAttributes["name"] = styleName

                for definition in style {
                    let compiled = ruleCompiler.compile(definition, existing: &existing)
                    for rule in compiled {
                        if let node = ruleCompiler.symbolizersToXML(rule) {
                            switch node {
                            case let .element(element):
                                styleContent.append(.element(element))
                            }
                        }
                    }
                }
                evaluator = ruleCompiler.evaluator

                // Universal style attributes: comp-op / opacity / image-filters
                // (carto's StyleObject)
                if let styleAttrs = Self.styleAttributes(style, evaluator: &evaluator, messages: &localMessages) {
                    for (key, value) in styleAttrs {
                        styleAttributes[key] = value
                    }
                }

                if !styleContent.isEmpty {
                    output.append(.element(XMLNode.Element(name: "Style", attributes: styleAttributes, children: styleContent)))
                    styles.append(styleName)
                }
            }

            // carto: m._properties[layerId] merged under the layer's own
            // properties (layer wins).
            var layer = layer
            if let global = mml.globalProperties[layer.id] {
                var merged: [(String, JSONValue)] = global
                if let own = layer.properties {
                    for (key, value) in own {
                        if let index = merged.firstIndex(where: { $0.0 == key }) {
                            merged[index] = (key, value)
                        }
                        else {
                            merged.append((key, value))
                        }
                    }
                }
                layer.properties = merged
            }
            output.append(.element(Self.layerNode(layer, styles: styles)))
        }

        for fontSet in evaluator.fontSets {
            fontSetNodes.append(.element(fontSetNode(fontSet)))
        }

        if !fontSetNodes.isEmpty {
            output = fontSetNodes + output
        }

        let parameterNodes = Renderer.mapParameterNodes(mml)
        if !parameterNodes.isEmpty {
            output.insert(.element(XMLNode.element("Parameters", content: parameterNodes)), at: 0)
        }

        let root = XMLNode.Element(name: "Map", attributes: mapAttributes, children: output)

        messages = localMessages.items
        if localMessages.hasErrors {
            return nil
        }

        var result = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!DOCTYPE Map[]>\n"
        result += XMLSerializer.serialize(root)
        return result
    }

    private func fontSetNode(_ fontSet: FontSet) -> XMLNode.Element {
        var fonts: [XMLNode] = []
        for font in fontSet.fonts {
            fonts.append(.element(XMLNode.element("Font", attributes: ["face-name": font])))
        }
        return XMLNode.Element(
            name: "FontSet", attributes: ["name": fontSet.name], children: fonts)
    }

    /// Style-level comp-op/opacity/image-filters attributes (carto's
    /// `tree.StyleObject`).
    private static func styleAttributes(
        _ style: [Definition], evaluator: inout Evaluator, messages: inout Messages,
    ) -> [String: String]? {
        var compOp: String?
        var opacity: String?
        var imageFilters: [String] = []
        var imageFiltersInflate: String?
        var directImageFilters: [String] = []
        var seenFilterIds: Set<String> = []

        for definition in style {
            for rule in definition.rules {
                switch rule.name {
                case "comp-op":
                    let evaluated = evaluator.evaluateValue(rule.value)
                    if case let .keyword(value) = evaluated, value != "none", value != "src-over" {
                        compOp = value
                    }

                case "opacity":
                    let evaluated = evaluator.evaluateValue(rule.value)
                    if case let .dimension(d) = evaluated, d.value != 1 {
                        opacity = formatNumber(d.value)
                    }

                case "direct-image-filters", "image-filters":
                    let evaluated = evaluator.evaluateValue(rule.value)
                    if case let .keyword(value) = evaluated, value == "none" {
                        continue
                    }
                    if seenFilterIds.contains(rule.id) {
                        continue
                    }
                    seenFilterIds.insert(rule.id)
                    // carto passes sep=',' — comma-separated entities join
                    // without spaces.
                    let serialized: String = if case let .value(value) = evaluated {
                        value.values
                            .map {
                                RuleCompiler.serialize($0, &messages, rule.filename, rule.index)
                            }
                            .joined(separator: ",")
                    }
                    else {
                        RuleCompiler.serialize(
                            evaluated, &messages, rule.filename, rule.index)
                    }
                    if !serialized.isEmpty {
                        if rule.name == "image-filters" {
                            imageFilters.append(serialized)
                        }
                        else {
                            directImageFilters.append(serialized)
                        }
                    }

                case "image-filters-inflate":
                    let evaluated = evaluator.evaluateValue(rule.value)
                    imageFiltersInflate = RuleCompiler.serialize(
                        evaluated, &messages, rule.filename, rule.index)

                default:
                    break
                }
            }
        }

        var result: [String: String] = [:]
        if let compOp {
            result["comp-op"] = compOp
        }
        if let opacity {
            result["opacity"] = opacity
        }
        if !imageFilters.isEmpty {
            result["image-filters"] = imageFilters.joined(separator: ",")
        }
        if let imageFiltersInflate {
            result["image-filters-inflate"] = imageFiltersInflate
        }
        if !directImageFilters.isEmpty {
            result["direct-image-filters"] = directImageFilters.joined(separator: ",")
        }
        return result.isEmpty ? nil : result
    }

    /// carto's `tree.LayerObject`.
    static func layerNode(_ layer: MML.Layer, styles: [String]) -> XMLNode.Element {
        var attributes: [String: String] = [:]
        attributes["name"] = layer.id

        if let status = layer.status {
            attributes["status"] = status
        }
        if let srs = layer.srs {
            attributes["srs"] = srs
        }
        // Layer-level properties (carto's LayerObject): minzoom/maxzoom map
        // to scale denominators (API >= 3.0.0), the rest pass through as
        // attributes.
        if let properties = layer.properties {
            for (key, value) in properties {
                switch key {
                case "minzoom":
                    if let zoom = value.intValue {
                        attributes["maximum-scale-denominator"] = formatNumber(Zoom.ranges[zoom] ?? 0)
                    }
                    continue

                case "maxzoom":
                    if let zoom = value.intValue {
                        attributes["minimum-scale-denominator"] = formatNumber(Zoom.ranges[zoom + 1] ?? 0)
                    }
                    continue

                default:
                    break
                }
                let stringValue: String
                switch value {
                case let .string(s): stringValue = s
                case let .number(n): stringValue = formatNumber(n)
                case let .bool(b): stringValue = b ? "true" : "false"
                default: continue
                }
                attributes[key] = stringValue
            }
        }

        var children: [XMLNode] = []
        // carto pushes styles.reverse() into the layer.
        for style in styles.reversed() {
            children.append(.element(XMLNode.Element(name: "StyleName", content: style, cdata: true)))
        }

        if let datasource = layer.datasource {
            var parameters: [XMLNode] = []
            for (key, value) in datasource.values {
                let stringValue: String
                var isCDATA = false
                switch value {
                case let .string(s):
                    stringValue = s
                    isCDATA = true

                case let .number(n): stringValue = formatNumber(n)

                case let .bool(b): stringValue = b ? "true" : "false"

                case .null: stringValue = ""

                default: stringValue = value.serialized().replacingOccurrences(of: "\n", with: "")
                }
                parameters.append(
                    .element(
                        XMLNode.Element(
                            name: "Parameter", attributes: ["name": key], children: [],
                            content: stringValue, cdata: isCDATA)))
            }
            if !parameters.isEmpty {
                children.append(.element(XMLNode.element("Datasource", content: parameters)))
            }
        }

        return XMLNode.Element(name: "Layer", attributes: attributes, children: children)
    }

    /// Top-level `<Parameters>` carto passes through (bounds, center, ...),
    /// in the MML document's property order (carto iterates the object).
    static func mapParameterNodes(_ mml: MML) -> [XMLNode] {
        guard let rawMembers = mml.rawMembers else { return [] }

        var parameters: [XMLNode] = []

        func add(_ name: String, _ value: JSONValue?) {
            guard let value else { return }

            // carto skips falsy values (empty strings, false, null) unless 0.
            if case let .string(s) = value, s.isEmpty {
                return
            }
            if case .bool(false) = value {
                return
            }
            // Strings serialize as CDATA; numbers/bools/arrays as plain text
            // (carto's jsonToXML).
            let stringValue: String
            var isCDATA = false
            switch value {
            case let .string(s):
                stringValue = s
                isCDATA = true

            case let .number(n): stringValue = formatNumber(n)

            case .bool: stringValue = "true"

            case .null: return

            case let .array(values):
                stringValue =
                    values.map {
                        switch $0 {
                        case let .string(s): s
                        case let .number(n): formatNumber(n)
                        case let .bool(b): b ? "true" : "false"
                        default: ""
                        }
                    }
                    .joined(separator: ",")

            default: return
            }
            parameters.append(
                .element(
                    XMLNode.Element(
                        name: "Parameter", attributes: ["name": name], children: [],
                        content: stringValue, cdata: isCDATA)))
        }

        for (key, value) in rawMembers {
            switch key {
            case "Layer", "srs", "Stylesheet":
                continue

            case "interactivity":
                add("interactivity_layer", value.objectDictionary?["layer"])
                add("interactivity_fields", value.objectDictionary?["fields"])

            default:
                add(key, value)
            }
        }

        return parameters
    }

}

extension XMLNode.Element {

    init(
        name: String,
        attributes: [String: String] = [:],
        content: String,
        cdata: Bool,
    ) {
        self.init(
            name: name,
            attributes: attributes,
            children: [],
            content: content,
            cdata: cdata)
    }

}
