//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// A color stored in HSL (hue 0–360, s/l 0–1) plus alpha, mirroring
/// carto's `tree.Color`. Supports the `hsluv` perceptual variant used by
/// the `*p` color functions (rarely used; kept for completeness).
public struct Color: Sendable, Equatable {

    public var h: Double
    public var s: Double
    public var l: Double
    public var alpha: Double
    public var perceptual: Bool

    public init(h: Double, s: Double, l: Double, alpha: Double = 1, perceptual: Bool = false) {
        self.h = max(0, min(h, 360))
        self.s = max(0, min(s, 1))
        self.l = max(0, min(l, 1))
        self.alpha = alpha
        self.perceptual = perceptual
    }

    /// Build from an RGB triplet (0–255).
    public init(rgb: [Double], alpha: Double = 1) {
        let hsl = Color.rgbToHSL(rgb)
        self.init(h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha)
    }

    // MARK: - Conversions

    /// RGB in 0–255. Matches chroma-js's hsl→rgb rounding: each channel is
    /// `Math.round(c)` of the 0–255 float.
    public var rgb: [Double] {
        let (r, g, b) = Color.hslToRGB(h: h, s: s, l: l)
        return [floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)]
    }

    /// HSL to RGB, h in 0–360, s/l in 0–1. Returns 0–1 floats.
    static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        /// The algorithm chroma-js uses (W3C formula).
        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 {
                t += 1
            }
            if t > 1 {
                t -= 1
            }
            if t < 1.0 / 6.0 {
                return p + (q - p) * 6 * t
            }
            if t < 1.0 / 2.0 {
                return q
            }
            if t < 2.0 / 3.0 {
                return p + (q - p) * (2.0 / 3.0 - t) * 6
            }
            return p
        }

        if s == 0 {
            return (l, l, l)
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let hue = h / 360
        return (
            hueToRGB(p, q, hue + 1.0 / 3.0),
            hueToRGB(p, q, hue),
            hueToRGB(p, q, hue - 1.0 / 3.0),
        )
    }

    /// RGB (0–1) to HSL. Returns (h 0–360, s 0–1, l 0–1). Hue is NaN for
    /// achromatic colors (chroma-js behavior).
    static func rgbToHSL(_ rgb: [Double]) -> (Double, Double, Double) {
        var r = (rgb.first ?? 0) / 255
        var g = (rgb.count > 1 ? rgb[1] : rgb.first ?? 0) / 255
        var b = (rgb.count > 2 ? rgb[2] : rgb.first ?? 0) / 255
        r = max(0, min(r, 1))
        g = max(0, min(g, 1))
        b = max(0, min(b, 1))

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2

        if maxC == minC {
            return (.nan, 0, l)
        }

        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)

        var h: Double = switch maxC {
        case r: (g - b) / d + (g < b ? 6 : 0)
        case g: (b - r) / d + 2
        default: (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    // MARK: - Output formatting

    /// The XML attribute form: `#rrggbb` when fully opaque, `rgba(r, g, b, a)`
    /// otherwise — matching chroma-js hex output (2-digit lowercase hex).
    public func serialized() -> String {
        if alpha < 1.0 {
            let components = rgb.map { Int($0) }
            let roundedAlpha = (alpha * 100).rounded() / 100
            return "rgba(\(components.map(String.init).joined(separator: ", ")), \(formatNumber(roundedAlpha)))"
        }
        else {
            return hexString
        }
    }

    public var hexString: String {
        let components = rgb.map { Int($0) }
        return "#" + components.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Operations

    static func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    /// Channel-wise arithmetic in RGB space (carto's `color.operate`).
    func operate(_ op: Operation.Op, _ other: Node) -> Color? {
        let rgb2: [Double]
        switch other {
        case let .color(c):
            rgb2 = c.rgb
        case let .dimension(d):
            rgb2 = [d.value, d.value, d.value]
        default:
            return nil
        }

        let rgb1 = rgb
        var result: [Double] = []
        for c in 0 ..< 3 {
            let a = rgb1[c]
            let b = rgb2[c]
            switch op {
            case .add: result.append(a + b)
            case .subtract: result.append(a - b)
            case .multiply: result.append(a * b)
            case .divide: result.append(a / b)
            case .modulo: result.append(a.truncatingRemainder(dividingBy: b))
            }
        }

        let hsl = Color.rgbToHSL(result)
        return Color(
            h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha, perceptual: false)
    }

}
