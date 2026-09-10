//
//  Created by Thomas Rasch, 2026.
//

import Foundation
import Synchronization

/// The mapnik reference: property tables per symbolizer plus named colors
/// and known functions, extracted from mapnik-reference v8.10 (v3.0.22).
///
/// carto validates property names and values against this data. We encode
/// the subset needed for validation and XML serialization; unknown
/// properties produce the same "Unrecognized rule" errors carto gives.
struct Reference {

    struct Property {

        let css: String
        let symbolizer: String
        /// The XML attribute name (e.g. `line-color` → `stroke`).
        let xmlName: String
        let type: String?
        let required: Bool
        /// `content` for text-name/shield-name (element content serialization).
        let serialization: String?
        let defaultValue: JSONValue?
        /// Keyword options for `type: [a, b]`-style values.
        let options: [String]?
        let status: String?

        init(
            css: String,
            symbolizer: String,
            xmlName: String,
            type: String? = nil,
            required: Bool = false,
            serialization: String? = nil,
            defaultValue: JSONValue? = nil,
            options: [String]? = nil,
            status: String? = nil,
        ) {
            self.css = css
            self.symbolizer = symbolizer
            self.xmlName = xmlName
            self.type = type
            self.required = required
            self.serialization = serialization
            self.defaultValue = defaultValue
            self.options = options
            self.status = status
        }
    }

    static let shared: Reference = .init()

    nonisolated(unsafe) static var propertiesByCSS: [String: Property] = [:]
    nonisolated(unsafe) static var symbolizerOrder: [String] = []
    nonisolated(unsafe) static var requiredBySymbolizer: [String: [String]] = [:]

    /// Named colors (CSS color keywords) from the reference.
    static let colors: [String: [Double]] = colorTable()

    /// Valid keyword literals in filter expressions (reference `filter`).
    static let filterKeywords: Set<String> = [
        "true", "false", "null", "point", "linestring", "polygon", "collection",
    ]

    /// Functions allowed by the reference (geometry transforms etc.) with
    /// their argument counts (-1 = variable).
    static let functions: [String: [Int]] = [
        "matrix": [6], "translate": [1, 2], "scale": [1, 2],
        "rotate": [3], "skewX": [1], "skewY": [1],
    ]

    func property(_ css: String) -> Property? {
        Self.loadProperties()
        return Self.propertiesByCSS[css]
    }

    func symbolizer(forCSS css: String) -> String? {
        Self.loadProperties()
        return Self.propertiesByCSS[css]?.symbolizer
    }

    func status(forCSS css: String) -> String {
        Self.loadProperties()
        return Self.propertiesByCSS[css]?.status ?? "stable"
    }

    /// Required properties for a symbolizer, e.g. `text-name` for text.
    func requiredProperties(for symbolizer: String) -> [String] {
        Self.loadProperties()
        return Self.requiredBySymbolizer[symbolizer] ?? []
    }

    /// Load the property tables (idempotent and thread-safe; called lazily
    /// from the property accessors and eagerly from `Renderer.init`).
    ///
    /// The tables are plain statics written by `buildProperties()`; the lock
    /// makes the "first writer wins, everyone waits" pattern safe under
    /// concurrent `Renderer` construction (which happens when a server
    /// compiles several projects in parallel).
    static func loadProperties() {
        if !propertiesLoaded.load(ordering: .acquiring) {
            loadLock.lock()
            defer { loadLock.unlock() }
            if !propertiesLoaded.load(ordering: .acquiring) {
                _ = buildProperties()
                propertiesLoaded.store(true, ordering: .releasing)
            }
        }
    }

    private static let loadLock: NSLock = .init()
    private static let propertiesLoaded = Synchronization.Atomic<Bool>(false)

    static func colorTable() -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for line in colorLines {
            let parts = line.split(separator: " ")
            guard parts.count >= 4 else { continue }

            var rgb: [Double] = [
                Double(String(parts[1])) ?? 0, Double(String(parts[2])) ?? 0,
                Double(String(parts[3])) ?? 0,
            ]
            if parts.count > 4 {
                // Alpha (carto's keywordcolor reads data[3] as alpha).
                rgb.append(Double(String(parts[4])) ?? 1)
            }
            result[String(parts[0])] = rgb
        }
        return result
    }

    /// Generated from mapnik-reference v3.0.22 colors.json:
    static let colorLines: [String] = [
        "aliceblue 240 248 255",
        "antiquewhite 250 235 215",
        "aqua 0 255 255",
        "aquamarine 127 255 212",
        "azure 240 255 255",
        "beige 245 245 220",
        "bisque 255 228 196",
        "black 0 0 0",
        "blanchedalmond 255 235 205",
        "blue 0 0 255",
        "blueviolet 138 43 226",
        "brown 165 42 42",
        "burlywood 222 184 135",
        "cadetblue 95 158 160",
        "chartreuse 127 255 0",
        "chocolate 210 105 30",
        "coral 255 127 80",
        "cornflowerblue 100 149 237",
        "cornsilk 255 248 220",
        "crimson 220 20 60",
        "cyan 0 255 255",
        "darkblue 0 0 139",
        "darkcyan 0 139 139",
        "darkgoldenrod 184 134 11",
        "darkgray 169 169 169",
        "darkgreen 0 100 0",
        "darkgrey 169 169 169",
        "darkkhaki 189 183 107",
        "darkmagenta 139 0 139",
        "darkolivegreen 85 107 47",
        "darkorange 255 140 0",
        "darkorchid 153 50 204",
        "darkred 139 0 0",
        "darksalmon 233 150 122",
        "darkseagreen 143 188 143",
        "darkslateblue 72 61 139",
        "darkslategrey 47 79 79",
        "darkturquoise 0 206 209",
        "darkviolet 148 0 211",
        "deeppink 255 20 147",
        "deepskyblue 0 191 255",
        "dimgray 105 105 105",
        "dimgrey 105 105 105",
        "dodgerblue 30 144 255",
        "firebrick 178 34 34",
        "floralwhite 255 250 240",
        "forestgreen 34 139 34",
        "fuchsia 255 0 255",
        "gainsboro 220 220 220",
        "ghostwhite 248 248 255",
        "gold 255 215 0",
        "goldenrod 218 165 32",
        "gray 128 128 128",
        "green 0 128 0",
        "greenyellow 173 255 47",
        "grey 128 128 128",
        "honeydew 240 255 240",
        "hotpink 255 105 180",
        "indianred 205 92 92",
        "indigo 75 0 130",
        "ivory 255 255 240",
        "khaki 240 230 140",
        "lavender 230 230 250",
        "lavenderblush 255 240 245",
        "lawngreen 124 252 0",
        "lemonchiffon 255 250 205",
        "lightblue 173 216 230",
        "lightcoral 240 128 128",
        "lightcyan 224 255 255",
        "lightgoldenrodyellow 250 250 210",
        "lightgray 211 211 211",
        "lightgreen 144 238 144",
        "lightgrey 211 211 211",
        "lightpink 255 182 193",
        "lightsalmon 255 160 122",
        "lightseagreen 32 178 170",
        "lightskyblue 135 206 250",
        "lightslategray 119 136 153",
        "lightslategrey 119 136 153",
        "lightsteelblue 176 196 222",
        "lightyellow 255 255 224",
        "lime 0 255 0",
        "limegreen 50 205 50",
        "linen 250 240 230",
        "magenta 255 0 255",
        "maroon 128 0 0",
        "mediumaquamarine 102 205 170",
        "mediumblue 0 0 205",
        "mediumorchid 186 85 211",
        "mediumpurple 147 112 219",
        "mediumseagreen 60 179 113",
        "mediumslateblue 123 104 238",
        "mediumspringgreen 0 250 154",
        "mediumturquoise 72 209 204",
        "mediumvioletred 199 21 133",
        "midnightblue 25 25 112",
        "mintcream 245 255 250",
        "mistyrose 255 228 225",
        "moccasin 255 228 181",
        "navajowhite 255 222 173",
        "navy 0 0 128",
        "oldlace 253 245 230",
        "olive 128 128 0",
        "olivedrab 107 142 35",
        "orange 255 165 0",
        "orangered 255 69 0",
        "orchid 218 112 214",
        "palegoldenrod 238 232 170",
        "palegreen 152 251 152",
        "paleturquoise 175 238 238",
        "palevioletred 219 112 147",
        "papayawhip 255 239 213",
        "peachpuff 255 218 185",
        "peru 205 133 63",
        "pink 255 192 203",
        "plum 221 160 221",
        "powderblue 176 224 230",
        "purple 128 0 128",
        "red 255 0 0",
        "rosybrown 188 143 143",
        "royalblue 65 105 225",
        "saddlebrown 139 69 19",
        "salmon 250 128 114",
        "sandybrown 244 164 96",
        "seagreen 46 139 87",
        "seashell 255 245 238",
        "sienna 160 82 45",
        "silver 192 192 192",
        "skyblue 135 206 235",
        "slateblue 106 90 205",
        "slategray 112 128 144",
        "slategrey 112 128 144",
        "snow 255 250 250",
        "springgreen 0 255 127",
        "steelblue 70 130 180",
        "tan 210 180 140",
        "teal 0 128 128",
        "thistle 216 191 216",
        "tomato 255 99 71",
        "transparent 0 0 0 0",
        "turquoise 64 224 208",
        "violet 238 130 238",
        "wheat 245 222 179",
        "white 255 255 255",
        "whitesmoke 245 245 245",
        "yellow 255 255 0",
        "yellowgreen 154 205 50",
    ]
}

extension Reference {

    /// All properties from mapnik-reference v3.0.22.
    static func buildProperties() -> [String: Property] {
        let properties: [Property] = [
            Property(css: "image-filters", symbolizer: "*", xmlName: "image-filters", type: "functions", required: false),
            Property(css: "image-filters-inflate", symbolizer: "*", xmlName: "image-filters-inflate", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "direct-image-filters", symbolizer: "*", xmlName: "direct-image-filters", type: "functions", required: false),
            Property(css: "comp-op", symbolizer: "*", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "opacity", symbolizer: "*", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "filter-mode", symbolizer: "*", xmlName: "filter-mode", type: nil, required: false, defaultValue: .string("all"), options: ["all", "first"]),
            Property(css: "background-color", symbolizer: "map", xmlName: "background-color", type: "color", required: false, defaultValue: .string("none")),
            Property(css: "background-image", symbolizer: "map", xmlName: "background-image", type: "uri", required: false, defaultValue: .string("")),
            Property(css: "background-image-comp-op", symbolizer: "map", xmlName: "background-image-comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "background-image-opacity", symbolizer: "map", xmlName: "background-image-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "srs", symbolizer: "map", xmlName: "srs", type: "string", required: false, defaultValue: .string("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs")),
            Property(css: "buffer-size", symbolizer: "map", xmlName: "buffer-size", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "maximum-extent", symbolizer: "map", xmlName: "maximum-extent", type: "string", required: false, defaultValue: .string("-20037508.34,-20037508.34,20037508.34,20037508.34")),
            Property(css: "base", symbolizer: "map", xmlName: "base", type: "string", required: false, defaultValue: .string("")),
            Property(css: "", symbolizer: "map", xmlName: "paths-from-xml", type: "boolean", required: false, defaultValue: .bool(true)),
            Property(css: "", symbolizer: "map", xmlName: "minimum-version", type: "string", required: false, defaultValue: .string("none")),
            Property(css: "font-directory", symbolizer: "map", xmlName: "font-directory", type: "uri", required: false, defaultValue: .string("none")),
            Property(css: "polygon", symbolizer: "polygon", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "polygon-fill", symbolizer: "polygon", xmlName: "fill", type: "color", required: false, defaultValue: .string("rgba(128,128,128,1)")),
            Property(css: "polygon-opacity", symbolizer: "polygon", xmlName: "fill-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "polygon-gamma", symbolizer: "polygon", xmlName: "gamma", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "polygon-gamma-method", symbolizer: "polygon", xmlName: "gamma-method", type: nil, required: false, defaultValue: .string("power"), options: ["power", "linear", "none", "threshold", "multiply"]),
            Property(css: "polygon-clip", symbolizer: "polygon", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "polygon-simplify", symbolizer: "polygon", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "polygon-simplify-algorithm", symbolizer: "polygon", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "polygon-smooth", symbolizer: "polygon", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "polygon-geometry-transform", symbolizer: "polygon", xmlName: "geometry-transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "polygon-comp-op", symbolizer: "polygon", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "line", symbolizer: "line", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "line-color", symbolizer: "line", xmlName: "stroke", type: "color", required: false, defaultValue: .string("black")),
            Property(css: "line-width", symbolizer: "line", xmlName: "stroke-width", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "line-opacity", symbolizer: "line", xmlName: "stroke-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "line-join", symbolizer: "line", xmlName: "stroke-linejoin", type: nil, required: false, defaultValue: .string("miter"), options: ["miter", "miter-revert", "round", "bevel"]),
            Property(css: "line-cap", symbolizer: "line", xmlName: "stroke-linecap", type: nil, required: false, defaultValue: .string("butt"), options: ["butt", "round", "square"]),
            Property(css: "line-gamma", symbolizer: "line", xmlName: "stroke-gamma", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "line-gamma-method", symbolizer: "line", xmlName: "stroke-gamma-method", type: nil, required: false, defaultValue: .string("power"), options: ["power", "linear", "none", "threshold", "multiply"]),
            Property(css: "line-dasharray", symbolizer: "line", xmlName: "stroke-dasharray", type: "numbers", required: false, defaultValue: .string("none")),
            Property(css: "line-dash-offset", symbolizer: "line", xmlName: "stroke-dashoffset", type: "numbers", required: false, defaultValue: .string("none")),
            Property(css: "line-miterlimit", symbolizer: "line", xmlName: "stroke-miterlimit", type: "float", required: false, defaultValue: .number(4)),
            Property(css: "line-clip", symbolizer: "line", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "line-simplify", symbolizer: "line", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "line-simplify-algorithm", symbolizer: "line", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "line-smooth", symbolizer: "line", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "line-offset", symbolizer: "line", xmlName: "offset", type: "float", required: false, defaultValue: .number(0), status: "unstable"),
            Property(css: "line-rasterizer", symbolizer: "line", xmlName: "rasterizer", type: nil, required: false, defaultValue: .string("full"), options: ["full", "fast"]),
            Property(css: "line-geometry-transform", symbolizer: "line", xmlName: "geometry-transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "line-comp-op", symbolizer: "line", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "marker", symbolizer: "markers", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "marker-file", symbolizer: "markers", xmlName: "file", type: "uri", required: false, defaultValue: .string("none")),
            Property(css: "marker-opacity", symbolizer: "markers", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "marker-fill-opacity", symbolizer: "markers", xmlName: "fill-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "marker-line-color", symbolizer: "markers", xmlName: "stroke", type: "color", required: false, defaultValue: .string("black")),
            Property(css: "marker-line-width", symbolizer: "markers", xmlName: "stroke-width", type: "float", required: false, defaultValue: .number(0.5)),
            Property(css: "marker-line-opacity", symbolizer: "markers", xmlName: "stroke-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "marker-placement", symbolizer: "markers", xmlName: "placement", type: nil, required: false, defaultValue: .string("point"), options: ["point", "line", "interior", "vertex-first", "vertex-last"]),
            Property(css: "marker-multi-policy", symbolizer: "markers", xmlName: "multi-policy", type: nil, required: false, defaultValue: .string("each"), options: ["each", "whole", "largest"]),
            Property(css: "marker-type", symbolizer: "markers", xmlName: "marker-type", type: nil, required: false, defaultValue: .string("ellipse"), options: ["arrow", "ellipse"], status: "deprecated"),
            Property(css: "marker-width", symbolizer: "markers", xmlName: "width", type: "float", required: false, defaultValue: .number(10)),
            Property(css: "marker-height", symbolizer: "markers", xmlName: "height", type: "float", required: false, defaultValue: .number(10)),
            Property(css: "marker-fill", symbolizer: "markers", xmlName: "fill", type: "color", required: false, defaultValue: .string("blue")),
            Property(css: "marker-allow-overlap", symbolizer: "markers", xmlName: "allow-overlap", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "marker-avoid-edges", symbolizer: "markers", xmlName: "avoid-edges", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "marker-ignore-placement", symbolizer: "markers", xmlName: "ignore-placement", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "marker-spacing", symbolizer: "markers", xmlName: "spacing", type: "float", required: false, defaultValue: .number(100)),
            Property(css: "marker-max-error", symbolizer: "markers", xmlName: "max-error", type: "float", required: false, defaultValue: .number(0.2)),
            Property(css: "marker-transform", symbolizer: "markers", xmlName: "transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "marker-clip", symbolizer: "markers", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "marker-simplify", symbolizer: "markers", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "marker-simplify-algorithm", symbolizer: "markers", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "marker-smooth", symbolizer: "markers", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "marker-geometry-transform", symbolizer: "markers", xmlName: "geometry-transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "marker-offset", symbolizer: "markers", xmlName: "offset", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "marker-comp-op", symbolizer: "markers", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "marker-direction", symbolizer: "markers", xmlName: "direction", type: nil, required: false, defaultValue: .string("right"), options: ["auto", "auto-down", "left", "right", "left-only", "right-only", "up", "down"]),
            Property(css: "shield", symbolizer: "shield", xmlName: "default", type: nil, required: false, options: ["none"], status: "unstable"),
            Property(css: "shield-name", symbolizer: "shield", xmlName: "name", type: "string", required: false, serialization: "content", defaultValue: .string("")),
            Property(css: "shield-file", symbolizer: "shield", xmlName: "file", type: "uri", required: true, defaultValue: .string("none")),
            Property(css: "shield-face-name", symbolizer: "shield", xmlName: "face-name", type: "font", required: true, defaultValue: .string("none")),
            Property(css: "shield-unlock-image", symbolizer: "shield", xmlName: "unlock-image", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "shield-size", symbolizer: "shield", xmlName: "size", type: "float", required: false, defaultValue: .number(10)),
            Property(css: "shield-fill", symbolizer: "shield", xmlName: "fill", type: "color", required: false, defaultValue: .string("black")),
            Property(css: "shield-placement", symbolizer: "shield", xmlName: "placement", type: nil, required: false, defaultValue: .string("point"), options: ["point", "line", "vertex", "interior", "grid", "alternating-grid"]),
            Property(css: "shield-avoid-edges", symbolizer: "shield", xmlName: "avoid-edges", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "shield-allow-overlap", symbolizer: "shield", xmlName: "allow-overlap", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "shield-margin", symbolizer: "shield", xmlName: "margin", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-repeat-distance", symbolizer: "shield", xmlName: "repeat-distance", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-min-distance", symbolizer: "shield", xmlName: "minimum-distance", type: "float", required: false, defaultValue: .number(0), status: "deprecated"),
            Property(css: "shield-spacing", symbolizer: "shield", xmlName: "spacing", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-min-padding", symbolizer: "shield", xmlName: "minimum-padding", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-label-position-tolerance", symbolizer: "shield", xmlName: "label-position-tolerance", type: "float", required: false, defaultValue: .string("shield-spacing/2.0")),
            Property(css: "shield-wrap-width", symbolizer: "shield", xmlName: "wrap-width", type: "unsigned", required: false, defaultValue: .number(0)),
            Property(css: "shield-wrap-before", symbolizer: "shield", xmlName: "wrap-before", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "shield-wrap-character", symbolizer: "shield", xmlName: "wrap-character", type: "string", required: false, defaultValue: .string("\" \"")),
            Property(css: "shield-halo-fill", symbolizer: "shield", xmlName: "halo-fill", type: "color", required: false, defaultValue: .string("white")),
            Property(css: "shield-halo-radius", symbolizer: "shield", xmlName: "halo-radius", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-halo-rasterizer", symbolizer: "shield", xmlName: "halo-rasterizer", type: nil, required: false, defaultValue: .string("full"), options: ["full", "fast"]),
            Property(css: "shield-halo-transform", symbolizer: "shield", xmlName: "halo-transform", type: "functions", required: false, defaultValue: .string("")),
            Property(css: "shield-halo-comp-op", symbolizer: "shield", xmlName: "halo-comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "shield-halo-opacity", symbolizer: "shield", xmlName: "halo-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "shield-character-spacing", symbolizer: "shield", xmlName: "character-spacing", type: "unsigned", required: false, defaultValue: .number(0)),
            Property(css: "shield-line-spacing", symbolizer: "shield", xmlName: "line-spacing", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-text-dx", symbolizer: "shield", xmlName: "dx", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-text-dy", symbolizer: "shield", xmlName: "dy", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-dx", symbolizer: "shield", xmlName: "shield-dx", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-dy", symbolizer: "shield", xmlName: "shield-dy", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-opacity", symbolizer: "shield", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "shield-text-opacity", symbolizer: "shield", xmlName: "text-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "shield-horizontal-alignment", symbolizer: "shield", xmlName: "horizontal-alignment", type: nil, required: false, defaultValue: .string("auto"), options: ["left", "middle", "right", "auto"]),
            Property(css: "shield-vertical-alignment", symbolizer: "shield", xmlName: "vertical-alignment", type: nil, required: false, defaultValue: .string("middle"), options: ["top", "middle", "bottom", "auto"]),
            Property(css: "shield-placement-type", symbolizer: "shield", xmlName: "placement-type", type: nil, required: false, defaultValue: .string("dummy"), options: ["dummy", "simple", "list"]),
            Property(css: "shield-placements", symbolizer: "shield", xmlName: "placements", type: "string", required: false, defaultValue: .string("")),
            Property(css: "shield-text-transform", symbolizer: "shield", xmlName: "text-transform", type: nil, required: false, defaultValue: .string("none"), options: ["none", "uppercase", "lowercase", "capitalize", "reverse"]),
            Property(css: "shield-justify-alignment", symbolizer: "shield", xmlName: "justify-alignment", type: nil, required: false, defaultValue: .string("auto"), options: ["left", "center", "right", "auto"]),
            Property(css: "shield-transform", symbolizer: "shield", xmlName: "transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "shield-clip", symbolizer: "shield", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "shield-simplify", symbolizer: "shield", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-simplify-algorithm", symbolizer: "shield", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "shield-smooth", symbolizer: "shield", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-comp-op", symbolizer: "shield", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "shield-grid-cell-width", symbolizer: "shield", xmlName: "grid-cell-width", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-grid-cell-height", symbolizer: "shield", xmlName: "grid-cell-height", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "shield-offset", symbolizer: "shield", xmlName: "offset", type: "float", required: false, defaultValue: .number(0), status: "unstable"),
            Property(css: "line-pattern", symbolizer: "line-pattern", xmlName: "default", type: nil, required: false, options: ["none"], status: "unstable"),
            Property(css: "line-pattern-type", symbolizer: "line-pattern", xmlName: "line-pattern", type: nil, required: false, defaultValue: .string("warp"), options: ["warp", "repeat"]),
            Property(css: "line-pattern-file", symbolizer: "line-pattern", xmlName: "file", type: "uri", required: true, defaultValue: .string("none")),
            Property(css: "line-pattern-clip", symbolizer: "line-pattern", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "line-pattern-opacity", symbolizer: "line-pattern", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "line-pattern-simplify", symbolizer: "line-pattern", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "line-pattern-simplify-algorithm", symbolizer: "line-pattern", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "line-pattern-smooth", symbolizer: "line-pattern", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "line-pattern-offset", symbolizer: "line-pattern", xmlName: "offset", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "line-pattern-geometry-transform", symbolizer: "line-pattern", xmlName: "geometry-transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "line-pattern-transform", symbolizer: "line-pattern", xmlName: "transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "line-pattern-comp-op", symbolizer: "line-pattern", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "line-pattern-alignment", symbolizer: "line-pattern", xmlName: "alignment", type: nil, required: false, defaultValue: .string("global"), options: ["global", "local"]),
            Property(css: "line-pattern-width", symbolizer: "line-pattern", xmlName: "stroke-width", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "line-pattern-cap", symbolizer: "line-pattern", xmlName: "stroke-linecap", type: nil, required: false, defaultValue: .string("butt"), options: ["butt", "round", "square"]),
            Property(css: "line-pattern-join", symbolizer: "line-pattern", xmlName: "stroke-linejoin", type: nil, required: false, defaultValue: .string("miter"), options: ["miter", "miter-revert", "round", "bevel"]),
            Property(css: "line-pattern-miterlimit", symbolizer: "line-pattern", xmlName: "stroke-miterlimit", type: "float", required: false, defaultValue: .number(4)),
            Property(css: "line-pattern-dasharray", symbolizer: "line-pattern", xmlName: "stroke-dasharray", type: "numbers", required: false, defaultValue: .string("none")),
            Property(css: "polygon-pattern", symbolizer: "polygon-pattern", xmlName: "default", type: nil, required: false, options: ["none"], status: "unstable"),
            Property(css: "polygon-pattern-file", symbolizer: "polygon-pattern", xmlName: "file", type: "uri", required: true, defaultValue: .string("none")),
            Property(css: "polygon-pattern-alignment", symbolizer: "polygon-pattern", xmlName: "alignment", type: nil, required: false, defaultValue: .string("global"), options: ["global", "local"]),
            Property(css: "polygon-pattern-gamma", symbolizer: "polygon-pattern", xmlName: "gamma", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "polygon-pattern-opacity", symbolizer: "polygon-pattern", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "polygon-pattern-clip", symbolizer: "polygon-pattern", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "polygon-pattern-simplify", symbolizer: "polygon-pattern", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "polygon-pattern-simplify-algorithm", symbolizer: "polygon-pattern", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "polygon-pattern-smooth", symbolizer: "polygon-pattern", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "polygon-pattern-geometry-transform", symbolizer: "polygon-pattern", xmlName: "geometry-transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "polygon-pattern-transform", symbolizer: "polygon-pattern", xmlName: "transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "polygon-pattern-comp-op", symbolizer: "polygon-pattern", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "raster", symbolizer: "raster", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "raster-opacity", symbolizer: "raster", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "raster-filter-factor", symbolizer: "raster", xmlName: "filter-factor", type: "float", required: false, defaultValue: .number(-1)),
            Property(css: "raster-scaling", symbolizer: "raster", xmlName: "scaling", type: nil, required: false, defaultValue: .string("near"), options: ["near", "fast", "bilinear", "bicubic", "spline16", "spline36", "hanning", "hamming", "hermite", "kaiser", "quadric", "catrom", "gaussian", "bessel", "mitchell", "sinc", "lanczos", "blackman"]),
            Property(css: "raster-mesh-size", symbolizer: "raster", xmlName: "mesh-size", type: "unsigned", required: false, defaultValue: .number(16)),
            Property(css: "raster-comp-op", symbolizer: "raster", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "raster-colorizer-default-mode", symbolizer: "raster", xmlName: "default-mode", type: nil, required: false, defaultValue: .string("linear"), options: ["discrete", "linear", "exact"]),
            Property(css: "raster-colorizer-default-color", symbolizer: "raster", xmlName: "default-color", type: "color", required: false, defaultValue: .string("transparent")),
            Property(css: "raster-colorizer-epsilon", symbolizer: "raster", xmlName: "epsilon", type: "float", required: false, defaultValue: .string("1.1920928955078125e-07")),
            Property(css: "raster-colorizer-stops", symbolizer: "raster", xmlName: "stop", type: "tags", required: false, serialization: "tag", defaultValue: .string("")),
            Property(css: "point", symbolizer: "point", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "point-file", symbolizer: "point", xmlName: "file", type: "uri", required: false, defaultValue: .string("none")),
            Property(css: "point-allow-overlap", symbolizer: "point", xmlName: "allow-overlap", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "point-ignore-placement", symbolizer: "point", xmlName: "ignore-placement", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "point-opacity", symbolizer: "point", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "point-placement", symbolizer: "point", xmlName: "placement", type: nil, required: false, defaultValue: .string("centroid"), options: ["centroid", "interior"]),
            Property(css: "point-transform", symbolizer: "point", xmlName: "transform", type: "functions", required: false, defaultValue: .string("none")),
            Property(css: "point-comp-op", symbolizer: "point", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "text", symbolizer: "text", xmlName: "default", type: nil, required: false, options: ["none"], status: "unstable"),
            Property(css: "text-name", symbolizer: "text", xmlName: "name", type: "string", required: true, serialization: "content", defaultValue: .string("none")),
            Property(css: "text-face-name", symbolizer: "text", xmlName: "face-name", type: "font", required: true, defaultValue: .string("none")),
            Property(css: "text-size", symbolizer: "text", xmlName: "size", type: "float", required: false, defaultValue: .number(10)),
            Property(css: "text-ratio", symbolizer: "text", xmlName: "text-ratio", type: "unsigned", required: false, defaultValue: .number(0)),
            Property(css: "text-wrap-width", symbolizer: "text", xmlName: "wrap-width", type: "unsigned", required: false, defaultValue: .number(0)),
            Property(css: "text-wrap-before", symbolizer: "text", xmlName: "wrap-before", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "text-wrap-character", symbolizer: "text", xmlName: "wrap-character", type: "string", required: false, defaultValue: .string("\" \"")),
            Property(css: "text-repeat-wrap-character", symbolizer: "text", xmlName: "repeat-wrap-character", type: "boolean", required: false, defaultValue: .bool(false), status: "unstable"),
            Property(css: "text-spacing", symbolizer: "text", xmlName: "spacing", type: "unsigned", required: false, defaultValue: .number(0)),
            Property(css: "text-character-spacing", symbolizer: "text", xmlName: "character-spacing", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-line-spacing", symbolizer: "text", xmlName: "line-spacing", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-label-position-tolerance", symbolizer: "text", xmlName: "label-position-tolerance", type: "float", required: false, defaultValue: .string("text-spacing/2.0")),
            Property(css: "text-max-char-angle-delta", symbolizer: "text", xmlName: "max-char-angle-delta", type: "float", required: false, defaultValue: .number(22.5)),
            Property(css: "text-fill", symbolizer: "text", xmlName: "fill", type: "color", required: false, defaultValue: .string("black")),
            Property(css: "text-opacity", symbolizer: "text", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "text-halo-opacity", symbolizer: "text", xmlName: "halo-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "text-halo-fill", symbolizer: "text", xmlName: "halo-fill", type: "color", required: false, defaultValue: .string("white")),
            Property(css: "text-halo-radius", symbolizer: "text", xmlName: "halo-radius", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-halo-rasterizer", symbolizer: "text", xmlName: "halo-rasterizer", type: nil, required: false, defaultValue: .string("full"), options: ["full", "fast"]),
            Property(css: "text-halo-transform", symbolizer: "text", xmlName: "halo-transform", type: "functions", required: false, defaultValue: .string("")),
            Property(css: "text-dx", symbolizer: "text", xmlName: "dx", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-dy", symbolizer: "text", xmlName: "dy", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-vertical-alignment", symbolizer: "text", xmlName: "vertical-alignment", type: nil, required: false, defaultValue: .string("auto"), options: ["top", "middle", "bottom", "auto"]),
            Property(css: "text-avoid-edges", symbolizer: "text", xmlName: "avoid-edges", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "text-margin", symbolizer: "text", xmlName: "margin", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-repeat-distance", symbolizer: "text", xmlName: "repeat-distance", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-min-distance", symbolizer: "text", xmlName: "minimum-distance", type: "float", required: false, defaultValue: .number(0), status: "deprecated"),
            Property(css: "text-min-padding", symbolizer: "text", xmlName: "minimum-padding", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-min-path-length", symbolizer: "text", xmlName: "minimum-path-length", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-allow-overlap", symbolizer: "text", xmlName: "allow-overlap", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "text-orientation", symbolizer: "text", xmlName: "orientation", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-rotate-displacement", symbolizer: "text", xmlName: "rotate-displacement", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "text-upright", symbolizer: "text", xmlName: "upright", type: nil, required: false, defaultValue: .string("auto"), options: ["auto", "auto-down", "left", "right", "left-only", "right-only"]),
            Property(css: "text-placement", symbolizer: "text", xmlName: "placement", type: nil, required: false, defaultValue: .string("point"), options: ["point", "line", "vertex", "interior", "grid", "alternating-grid"]),
            Property(css: "text-placement-type", symbolizer: "text", xmlName: "placement-type", type: nil, required: false, defaultValue: .string("dummy"), options: ["dummy", "simple", "list"]),
            Property(css: "text-placements", symbolizer: "text", xmlName: "placements", type: "string", required: false, defaultValue: .string("")),
            Property(css: "text-transform", symbolizer: "text", xmlName: "text-transform", type: nil, required: false, defaultValue: .string("none"), options: ["none", "uppercase", "lowercase", "capitalize", "reverse"]),
            Property(css: "text-horizontal-alignment", symbolizer: "text", xmlName: "horizontal-alignment", type: nil, required: false, defaultValue: .string("auto"), options: ["left", "middle", "right", "auto", "adjust"]),
            Property(css: "text-align", symbolizer: "text", xmlName: "justify-alignment", type: nil, required: false, defaultValue: .string("auto"), options: ["left", "right", "center", "auto"]),
            Property(css: "text-clip", symbolizer: "text", xmlName: "clip", type: "boolean", required: false, defaultValue: .bool(false)),
            Property(css: "text-simplify", symbolizer: "text", xmlName: "simplify", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-simplify-algorithm", symbolizer: "text", xmlName: "simplify-algorithm", type: nil, required: false, defaultValue: .string("radial-distance"), options: ["radial-distance", "zhao-saalfeld", "visvalingam-whyatt", "douglas-peucker"]),
            Property(css: "text-smooth", symbolizer: "text", xmlName: "smooth", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-comp-op", symbolizer: "text", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "text-halo-comp-op", symbolizer: "text", xmlName: "halo-comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
            Property(css: "text-font-feature-settings", symbolizer: "text", xmlName: "font-feature-settings", type: "string", required: false, defaultValue: .string("")),
            Property(css: "text-largest-bbox-only", symbolizer: "text", xmlName: "largest-bbox-only", type: "boolean", required: false, defaultValue: .bool(true), status: "experimental"),
            Property(css: "text-grid-cell-width", symbolizer: "text", xmlName: "grid-cell-width", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-grid-cell-height", symbolizer: "text", xmlName: "grid-cell-height", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "text-offset", symbolizer: "text", xmlName: "offset", type: "float", required: false, defaultValue: .number(0), status: "unstable"),
            Property(css: "building", symbolizer: "building", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "building-fill", symbolizer: "building", xmlName: "fill", type: "color", required: false, defaultValue: .string("The color gray will be used for fill.")),
            Property(css: "building-fill-opacity", symbolizer: "building", xmlName: "fill-opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "building-height", symbolizer: "building", xmlName: "height", type: "float", required: false, defaultValue: .number(0)),
            Property(css: "debug-mode", symbolizer: "debug", xmlName: "mode", type: nil, required: false, defaultValue: .string("collision"), options: ["collision", "vertex"]),
            Property(css: "dot", symbolizer: "dot", xmlName: "default", type: nil, required: false, options: ["auto", "none"], status: "unstable"),
            Property(css: "dot-fill", symbolizer: "dot", xmlName: "fill", type: "color", required: false, defaultValue: .string("gray")),
            Property(css: "dot-opacity", symbolizer: "dot", xmlName: "opacity", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "dot-width", symbolizer: "dot", xmlName: "width", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "dot-height", symbolizer: "dot", xmlName: "height", type: "float", required: false, defaultValue: .number(1)),
            Property(css: "dot-comp-op", symbolizer: "dot", xmlName: "comp-op", type: nil, required: false, defaultValue: .string("src-over"), options: ["clear", "src", "dst", "src-over", "dst-over", "src-in", "dst-in", "src-out", "dst-out", "src-atop", "dst-atop", "xor", "plus", "minus", "multiply", "divide", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "linear-dodge", "linear-burn", "hard-light", "soft-light", "difference", "exclusion", "contrast", "invert", "invert-rgb", "grain-merge", "grain-extract", "hue", "saturation", "color", "value"]),
        ]

        var result: [String: Property] = [:]
        var order: [String] = []
        var required: [String: [String]] = [:]
        for property in properties {
            result[property.css] = property
            if !order.contains(property.symbolizer) {
                order.append(property.symbolizer)
            }
            if property.required {
                required[property.symbolizer, default: []].append(property.css)
            }
        }
        propertiesByCSS = result
        symbolizerOrder = order
        requiredBySymbolizer = required
        return result
    }

}
