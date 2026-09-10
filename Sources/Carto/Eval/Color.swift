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
    /// `Math.round(c)` of the 0–255 float. Perceptual colors go through
    /// HSLuv → sRGB (carto's `tree.Color.toString`).
    public var rgb: [Double] {
        if perceptual {
            let components = HSLuv.hsluvToRGB([h, s * 100, l * 100])
            return components.map { floor($0 * 255 + 0.5) }
        }
        let (r, g, b) = Color.hslToRGB(h: h, s: s, l: l)
        return [floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)]
    }

    /// Perceptual variant of `rgb` as 0–1 floats (carto's
    /// `hsluv.hsluvToRgb([h, s*100, l*100])`).
    var rgbNormalized: [Double] {
        perceptual ? HSLuv.hsluvToRGB([h, s * 100, l * 100]) : [
            Color.hslToRGB(h: h, s: s, l: l).0,
            Color.hslToRGB(h: h, s: s, l: l).1,
            Color.hslToRGB(h: h, s: s, l: l).2,
        ]
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

    /// carto's `tree.Color.toPerceptual`: HSL → HSLuv via RGB.
    func toPerceptual() -> Color {
        if perceptual {
            return self
        }

        let (r, g, b) = Color.hslToRGB(h: h, s: s, l: l)
        let hsluv = HSLuv.rgbToHSLuv([r, g, b])
        return Color(h: hsluv[0], s: hsluv[1] / 100, l: hsluv[2] / 100, alpha: alpha, perceptual: true)
    }

    /// carto's `tree.Color.toStandard`: HSLuv → HSL via RGB.
    func toStandard() -> Color {
        if !perceptual {
            return self
        }

        let components = HSLuv.hsluvToRGB([h, s * 100, l * 100])
        let hsl = Color.rgbToHSL(components.map { floor($0 * 255 + 0.5) })
        return Color(h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha, perceptual: false)
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

        // carto's `tree.Color.operate`: convert the result back to the
        // color's own space (HSLuv for perceptual colors).
        if perceptual {
            let hsluv = HSLuv.rgbToHSLuv(result.map { $0 / 255 })
            return Color(
                h: hsluv[0], s: hsluv[1] / 100, l: hsluv[2] / 100, alpha: alpha,
                perceptual: true)
        }

        let hsl = Color.rgbToHSL(result)
        return Color(
            h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha, perceptual: false)
    }

    // MARK: - HSLuv (perceptual color space)

    /// HSLuv constants and conversions, a faithful port of the hsluv.org
    /// reference implementation (hsluv 0.0.2, the version carto depends on).
    enum HSLuv {

        /// Forward matrix sRGB → XYZ (D65) — `Hsluv.minv` in the reference.
        static let mInv: [[Double]] = [
            [0.41239079926595, 0.35758433938387, 0.18048078840183],
            [0.21263900587151, 0.71516867876775, 0.072192315360733],
            [0.019330818715591, 0.11919477979462, 0.95053215224966],
        ]

        /// XYZ → sRGB matrix (`Hsluv.m`).
        static let m: [[Double]] = [
            [3.240969941904521, -1.537383177570093, -0.498610760293],
            [-0.96924363628087, 1.87596750150772, 0.041555057407175],
            [0.055630079696993, -0.20397695888897, 1.056971514242878],
        ]

        static let refY = 1.0
        static let refU = 0.19783000664283
        static let refV = 0.46831999493879
        static let kappa = 903.2962962
        static let epsilon = 0.0088564516

        static func dotProduct(_ a: [Double], _ b: [Double]) -> Double {
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        }

        static func fromLinear(_ c: Double) -> Double {
            c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 0.416666666666666685) - 0.055
        }

        static func toLinear(_ c: Double) -> Double {
            c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
        }

        /// XYZ (D65, Y in 0–1) → sRGB (0–1).
        static func xyzToRGB(_ tuple: [Double]) -> [Double] {
            [
                fromLinear(dotProduct(m[0], tuple)),
                fromLinear(dotProduct(m[1], tuple)),
                fromLinear(dotProduct(m[2], tuple)),
            ]
        }

        /// sRGB (0–1) → XYZ.
        static func rgbToXYZ(_ tuple: [Double]) -> [Double] {
            let rgbl = [
                toLinear(tuple[0]), toLinear(tuple[1]), toLinear(tuple[2]),
            ]
            return [
                dotProduct(mInv[0], rgbl),
                dotProduct(mInv[1], rgbl),
                dotProduct(mInv[2], rgbl),
            ]
        }

        static func yToL(_ y: Double) -> Double {
            y <= epsilon ? y / refY * kappa : 116 * pow(y / refY, 1.0 / 3.0) - 16
        }

        static func lToY(_ l: Double) -> Double {
            l <= 8 ? refY * l / kappa : refY * pow((l + 16) / 116, 3)
        }

        static func xyzToLuv(_ tuple: [Double]) -> [Double] {
            let x = tuple[0]
            let y = tuple[1]
            let z = tuple[2]
            let divider = x + 15 * y + 3 * z
            var varU = 4 * x
            var varV = 9 * y
            if divider != 0 {
                varU /= divider
                varV /= divider
            }
            else {
                varU = .nan
                varV = .nan
            }
            let l = yToL(y)
            if l == 0 {
                return [0, 0, 0]
            }
            let u = 13 * l * (varU - refU)
            let v = 13 * l * (varV - refV)
            return [l, u, v]
        }

        static func luvToXYZ(_ tuple: [Double]) -> [Double] {
            let l = tuple[0]
            let u = tuple[1]
            let v = tuple[2]
            if l == 0 {
                return [0, 0, 0]
            }
            let varU = u / (13 * l) + refU
            let varV = v / (13 * l) + refV
            let y = lToY(l)
            let x = 0 - 9 * y * varU / ((varU - 4) * varV - varU * varV)
            let z = (9 * y - 15 * varV * y - varV * x) / (3 * varV)
            return [x, y, z]
        }

        static func luvToLCH(_ tuple: [Double]) -> [Double] {
            let l = tuple[0]
            let u = tuple[1]
            let v = tuple[2]
            let c = sqrt(u * u + v * v)
            var h: Double
            if c < 0.00000001 {
                h = 0
            }
            else {
                let hrad = atan2(v, u)
                h = hrad * 180.0 / .pi
                if h < 0 {
                    h = 360 + h
                }
            }
            return [l, c, h]
        }

        static func lchToLuv(_ tuple: [Double]) -> [Double] {
            let l = tuple[0]
            let c = tuple[1]
            let h = tuple[2]
            let hrad = h / 360.0 * 2 * Double.pi
            let u = cos(hrad) * c
            let v = sin(hrad) * c
            return [l, u, v]
        }

        /// The length of the ray from the origin in direction `hrad` until it
        /// leaves the sRGB gamut (the reference's `lengthOfRayUntilIntersect`).
        static func lengthOfRayUntilIntersect(_ theta: Double, _ slope: Double, _ intercept: Double) -> Double {
            intercept / (sin(theta) - slope * cos(theta))
        }

        static func getBounds(_ l: Double) -> [(slope: Double, intercept: Double)] {
            var result: [(Double, Double)] = []
            let sub1 = pow(l + 16, 3) / 1_560_896
            let sub2 = sub1 > epsilon ? sub1 : l / kappa
            for c in 0 ..< 3 {
                let m1 = m[c][0]
                let m2 = m[c][1]
                let m3 = m[c][2]
                for t in 0 ..< 2 {
                    let t = Double(t)
                    let top1 = (284_517 * m1 - 94839 * m3) * sub2
                    let top2 = (838_422 * m3 + 769_860 * m2 + 731_718 * m1) * l * sub2 - 769_860 * t * l
                    let bottom = (632_260 * m3 - 126_452 * m2) * sub2 + 126_452 * t
                    result.append((top1 / bottom, top2 / bottom))
                }
            }
            return result
        }

        static func maxChromaForLH(_ l: Double, _ h: Double) -> Double {
            let hrad = h / 360 * Double.pi * 2
            let bounds = getBounds(l)
            var min: Double = .infinity
            for bound in bounds {
                let length = lengthOfRayUntilIntersect(hrad, bound.slope, bound.intercept)
                if length >= 0 {
                    min = Swift.min(min, length)
                }
            }
            return min
        }

        /// HSLuv (h 0–360, s/l 0–100) → LCH.
        static func hsluvToLCH(_ tuple: [Double]) -> [Double] {
            let h = tuple[0]
            let s = tuple[1]
            let l = tuple[2]
            if l > 99.9999999 {
                return [100, 0, h]
            }
            if l < 0.00000001 {
                return [0, 0, h]
            }
            let max = maxChromaForLH(l, h)
            let c = max / 100 * s
            return [l, c, h]
        }

        /// LCH → HSLuv (h 0–360, s/l 0–100).
        static func lchToHSLuv(_ tuple: [Double]) -> [Double] {
            let l = tuple[0]
            let c = tuple[1]
            let h = tuple[2]
            if l > 99.9999999 {
                return [h, 0, 100]
            }
            if l < 0.00000001 {
                return [h, 0, 0]
            }
            let max = maxChromaForLH(l, h)
            let s = c / max * 100
            return [h, s, l]
        }

        /// HSLuv (h 0–360, s/l 0–100) → sRGB (0–1).
        static func hsluvToRGB(_ tuple: [Double]) -> [Double] {
            let lch = hsluvToLCH(tuple)
            let luv = lchToLuv(lch)
            let xyz = luvToXYZ(luv)
            return xyzToRGB(xyz)
        }

        /// sRGB (0–1) → HSLuv (h 0–360, s/l 0–100).
        static func rgbToHSLuv(_ tuple: [Double]) -> [Double] {
            let xyz = rgbToXYZ(tuple)
            let luv = xyzToLuv(xyz)
            let lch = luvToLCH(luv)
            return lchToHSLuv(lch)
        }

    }

}
