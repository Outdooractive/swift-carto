//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// A loaded CartoCSS project: the parsed `project.mml` document with its
/// stylesheets resolved to inline strings.
///
/// Mirrors carto's `MML.load`: JSON (or YAML) is parsed, the `Stylesheet`
/// property is normalized to an array, and string entries are read from disk
/// into `{ id, data }` objects.
public struct MML: Sendable {

    public struct Stylesheet: Sendable {
        public let id: String
        public let data: String

        public init(id: String, data: String) {
            self.id = id
            self.data = data
        }
    }

    public struct Layer: Sendable {
        public struct Datasource: Sendable {
            public var values: [(String, JSONValue)]

            public init(values: [(String, JSONValue)]) {
                self.values = values
            }
        }

        public let id: String
        public var name: String?
        public var classes: [String]
        public var srs: String?
        public var status: String?
        public var geometry: String?
        public var extent: [Double]?
        public var properties: [(String, JSONValue)]?
        public var datasource: Datasource?
        /// Any additional properties we don't model explicitly, passed through
        /// to the XML layer.
        public var extra: [String: JSONValue]

        public init(json: JSONValue) throws {
            guard let object = json.objectDictionary else {
                throw CartoError("Layer is not an object")
            }
            guard let id = object["id"]?.stringValue else {
                throw CartoError("The id attribute is required for layers")
            }

            self.id = id
            name = object["name"]?.stringValue
            if let `class` = object["class"]?.stringValue {
                classes = `class`.split(whereSeparator: { $0 == " " }).map(String.init)
            }
            else {
                classes = []
            }
            srs = object["srs"]?.stringValue
            status = object["status"]?.stringValue
            geometry = object["geometry"]?.stringValue
            if let extent = object["extent"]?.arrayValue {
                self.extent = extent.compactMap(\.doubleValue)
            }
            if case let .object(props)? = object["properties"] {
                properties = props
            }
            else {
                properties = nil
            }
            if case let .object(members)? = object["Datasource"] {
                datasource = Datasource(values: members)
            }
            else {
                datasource = nil
            }

            var extra: [String: JSONValue] = [:]
            for (key, value) in object {
                switch key {
                case "advanced", "class", "Datasource", "extent", "geometry", "id",
                     "name", "properties", "srs", "status":
                    continue
                default:
                    extra[key] = value
                }
            }
            self.extra = extra
        }
    }

    public var name: String?
    public var description: String?
    public var attribution: String?
    public var bounds: JSONValue?
    public var center: JSONValue?
    public var format: String?
    public var minzoom: Int?
    public var maxzoom: Int?
    public var srs: String?
    public var interactivity: JSONValue?
    public var scale: Double?
    public var metatile: Int?
    public var bufferSize: Int?
    public var stylesheets: [Stylesheet]
    public var layers: [Layer]
    /// Any additional scalar top-level properties, passed through as
    /// `<Parameter>`s (carto passes unknown scalar properties through).
    public var parameters: [String: JSONValue]
    /// The original top-level members in document order, for `<Parameters>`
    /// pass-through (carto iterates the object).
    public var rawMembers: [(String, JSONValue)]?
    /// Global per-layer properties from the `_properties` block (carto merges
    /// them under the layer's own properties).
    public var globalProperties: [String: [(String, JSONValue)]]

    /// Load an MML document from its JSON (or, with the
    /// `EnableYAMLProjectFiles` trait, YAML) representation. Relative
    /// stylesheet filenames are resolved against `basedir`.
    public init(data: String, basedir: URL?) throws {
        let json: JSONValue
        do {
            json = try JSONParser.parse(data)
        }
        catch {
            #if EnableYAMLProjectFiles
            // carto pipes every project file through js-yaml's `safeLoad`
            // (YAML is a superset of JSON); fall back to the YAML parser.
            json = try YAMLParser.parse(data)
            #else
            throw CartoError("carto: \(error)")
            #endif
        }

        guard case let .object(members) = json else {
            throw CartoError("MML document is not an object")
        }

        let object: Dictionary = .init(members, uniquingKeysWith: { _, rhs in rhs })

        // Stylesheet must exist and be an array (or a single object/string,
        // which we cast to an array).
        guard let stylesheetValue = object["Stylesheet"] else {
            throw CartoError(
                "Expecting a Stylesheet property containing an (array of) stylesheet object(s) " +
                    "of the form { id: 'x', 'data': 'y' }")
        }

        let stylesheetArray: [JSONValue] = if let array = stylesheetValue.arrayValue {
            array
        }
        else {
            [stylesheetValue]
        }

        var stylesheets: [Stylesheet] = []
        for stylesheet in stylesheetArray {
            // A plain string is a filename relative to the MML document;
            // an object must be { id, data }.
            if let file = stylesheet.stringValue {
                guard let basedir else {
                    throw CartoError(
                        "Expecting a stylesheet object of the form { id: 'x', 'data': 'y' } " +
                            "for the Stylesheet property.")
                }

                let fileURL = basedir.appendingPathComponent(file)
                do {
                    let contents = try String(contentsOf: fileURL, encoding: .utf8)
                    stylesheets.append(Stylesheet(id: file, data: contents))
                }
                catch {
                    throw CartoError("Failed to load file \(fileURL.path).")
                }
            }
            else if let id = stylesheet.objectDictionary?["id"]?.stringValue,
                    let data = stylesheet.objectDictionary?["data"]?.stringValue
            {
                stylesheets.append(Stylesheet(id: id, data: data))
            }
            else {
                throw CartoError(
                    "Expecting a stylesheet object of the form { id: 'x', 'data': 'y' } " +
                        "for the Stylesheet property.")
            }
        }
        self.stylesheets = stylesheets
        rawMembers = members
        if case let .object(props)? = object["_properties"] {
            globalProperties = Dictionary(
                props.map { ($0.0, $0.1.objectValue ?? []) },
                uniquingKeysWith: { _, rhs in rhs })
        }
        else {
            globalProperties = [:]
        }

        var layers: [Layer] = []
        if let layerArray = object["Layer"]?.arrayValue {
            for layerJSON in layerArray {
                try layers.append(Layer(json: layerJSON))
            }
        }
        self.layers = layers

        name = object["name"]?.stringValue
        description = object["description"]?.stringValue
        attribution = object["attribution"]?.stringValue
        bounds = object["bounds"]
        center = object["center"]
        format = object["format"]?.stringValue
        minzoom = object["minzoom"]?.intValue
        maxzoom = object["maxzoom"]?.intValue
        srs = object["srs"]?.stringValue
        interactivity = object["interactivity"]
        scale = object["scale"]?.doubleValue
        metatile = object["metatile"]?.intValue
        bufferSize = object["buffer-size"]?.intValue

        var parameters: [String: JSONValue] = [:]
        for (key, value) in object {
            switch key {
            case "_properties", "attribution", "bounds", "buffer-size", "center",
                 "description", "format", "interactivity", "Layer", "maxzoom",
                 "metatile", "minzoom", "name", "scale",
                 "srs", "Stylesheet":
                continue
            default:
                parameters[key] = value
            }
        }
        self.parameters = parameters
    }

}
