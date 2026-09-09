//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// The built-in color (and string) functions from carto's `functions.js`.
enum BuiltinFunction: String, CaseIterable {

    case rgb
    case rgba
    case hsl
    case hsla
    case hsluv
    case hsluva
    case hue
    case huep
    case saturation
    case saturationp
    case lightness
    case lightnessp
    case alpha
    case saturate
    case saturatep
    case desaturate
    case desaturatep
    case lighten
    case lightenp
    case darken
    case darkenp
    case fadein
    case fadeinp
    case fadeout
    case fadeoutp
    case spin
    case spinp
    case mix
    case greyscale
    case greyscalep
    case stop
    case emboss
    case blur
    case gray
    case sobel
    case edgeDetect = "edge-detect"
    case xGradient = "x-gradient"
    case yGradient = "y-gradient"
    case sharpen
    case aggStackBlur = "agg-stack-blur"
    case scaleHsla = "scale-hsla"
    case colorizeAlpha = "colorize-alpha"

    var arity: Int? {
        switch self {
        case .hsl, .hsluv, .mix, .rgb: 3
        case .darken, .darkenp, .desaturate, .desaturatep, .fadein, .fadeinp, .fadeout,
             .fadeoutp, .hsla, .hsluva, .lighten, .lightenp, .rgba, .saturate, .saturatep,
             .spin, .spinp:
            2
        case .alpha, .greyscale, .greyscalep, .hue, .huep, .lightness, .lightnessp,
             .saturation, .saturationp:
            1
        case .aggStackBlur, .blur, .colorizeAlpha, .edgeDetect, .emboss, .gray, .scaleHsla,
             .sharpen, .sobel, .stop, .xGradient, .yGradient:
            nil
        }
    }

    /// Execute the function with evaluated arguments.
    func call(
        _ args: [Node],
        _ messages: inout Messages,
        _ index: Int,
        _ filename: String?
    ) -> Node {
        if let arity, args.count < arity {
            messages.error(
                "incorrect number of arguments for \(rawValue)(). \(arity) expected.",
                filename: filename, index: index)
            return .undefined
        }

        switch self {
        case .rgb, .rgba:
            let numbers = args.map(\.percentNumberValue)
            if numbers.contains(nil) { return invalid(&messages, index, filename) }
            let alpha = self == .rgba ? (args.count > 3 ? args[3].numberValue ?? 1 : 1) : 1
            _ = numbers.compactMap(\.self).prefix(3).map { max(0, min($0, 255)) }
            let hsl = Color.rgbToHSL(Array(clampedRGB(args)))
            return .color(Color(h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha))

        case .hsl, .hsla:
            let h = args.count > 0 ? args[0].percentNumberValue ?? 0 : 0
            let s = args.count > 1 ? args[1].percentNumberValue ?? 0 : 0
            let l = args.count > 2 ? args[2].percentNumberValue ?? 0 : 0
            let a = args.count > 3 ? args[3].percentNumberValue ?? 1 : 1
            return .color(Color(h: h, s: s, l: l, alpha: a))

        case .hsluv, .hsluva:
            // Perceptual variant: not supported in the corpus; fall back to
            // plain HSL math on the same arguments.
            let h = args.count > 0 ? args[0].percentNumberValue ?? 0 : 0
            let s = args.count > 1 ? args[1].percentNumberValue ?? 0 : 0
            let l = args.count > 2 ? args[2].percentNumberValue ?? 0 : 0
            let a = args.count > 3 ? args[3].percentNumberValue ?? 1 : 1
            return .color(Color(h: h, s: s, l: l, alpha: a))

        case .hue:
            guard let color = args.first?.color else { return invalid(&messages, index, filename) }

            return .dimension(Dimension(value: color.h.rounded(), unit: nil))

        case .huep:
            guard let color = args.first?.color else { return invalid(&messages, index, filename) }

            return .color(color)

        case .lightness, .saturation:
            guard let color = args.first?.color else { return invalid(&messages, index, filename) }

            let value = self == .saturation ? color.s : color.l
            return .dimension(Dimension(value: (value * 100).rounded(), unit: "%"))

        case .alpha, .lightnessp, .saturationp:
            guard let color = args.first?.color else { return invalid(&messages, index, filename) }

            return .dimension(Dimension(value: color.alpha, unit: nil))

        case .desaturate, .saturate:
            guard var color = args.first?.color, args.count > 1,
                  let amount = args[1].numberValue
            else { return invalid(&messages, index, filename) }

            let delta = amount / 100 * (self == .saturate ? 1 : -1)
            color.s = Color.clamp(color.s + delta)
            return .color(color)

        case .desaturatep, .saturatep:
            return args.first ?? .undefined

        case .darken, .lighten:
            guard var color = args.first?.color, args.count > 1,
                  let amount = args[1].numberValue
            else { return invalid(&messages, index, filename) }

            let delta = amount / 100 * (self == .lighten ? 1 : -1)
            color.l = Color.clamp(color.l + delta)
            return .color(color)

        case .darkenp, .lightenp:
            return args.first ?? .undefined

        case .fadein, .fadeout:
            guard var color = args.first?.color, args.count > 1,
                  let amount = args[1].numberValue
            else { return invalid(&messages, index, filename) }

            let delta = amount / 100 * (self == .fadein ? 1 : -1)
            color.alpha = Color.clamp(color.alpha + delta)
            return .color(color)

        case .fadeinp, .fadeoutp:
            return args.first ?? .undefined

        case .spin:
            guard var color = args.first?.color, args.count > 1,
                  let amount = args[1].numberValue
            else { return invalid(&messages, index, filename) }

            var hue = (color.h + amount).truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
            color.h = hue
            return .color(color)

        case .spinp:
            return args.first ?? .undefined

        case .mix:
            guard let c1 = args.first?.color, args.count > 2, let c2 = args[1].color,
                  let weight = args[2].numberValue
            else { return invalid(&messages, index, filename) }

            let rgb1 = c1.rgb
            let rgb2 = c2.rgb
            let p = weight / 100.0
            let alpha = c1.alpha * p + c2.alpha * (1 - p)
            let a = c1.alpha - c2.alpha

            let w = p * 2 - 1
            let w1 = (((w * a == -1) ? w : (w + a) / (1 + w * a)) + 1) / 2.0
            let w2 = 1 - w1

            let rgb = [
                rgb1[0] * w1 + rgb2[0] * w2,
                rgb1[1] * w1 + rgb2[1] * w2,
                rgb1[2] * w1 + rgb2[2] * w2,
            ]
            let hsl = Color.rgbToHSL(rgb)
            return .color(Color(h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha))

        case .greyscale:
            guard var color = args.first?.color else { return invalid(&messages, index, filename) }

            color.s = Color.clamp(color.s - 1)
            return .color(color)

        case .greyscalep:
            return args.first ?? .undefined

        case .blur, .edgeDetect, .emboss, .gray, .sharpen, .sobel, .xGradient, .yGradient:
            return .imageFilter(name: rawValue, args: [])

        case .aggStackBlur, .colorizeAlpha, .scaleHsla:
            return .imageFilter(name: rawValue, args: args)

        case .stop:
            guard args.count >= 1 else { return invalid(&messages, index, filename) }

            var attributes: [(String, String)] = []
            attributes.append(("value", RuleCompiler.serialize(args[0], &messages, filename, index)))
            if args.count > 1 {
                attributes.append(("color", RuleCompiler.serialize(args[1], &messages, filename, index)))
            }
            if args.count > 2 {
                attributes.append(("mode", RuleCompiler.serialize(args[2], &messages, filename, index)))
            }
            return .tag(TagNode(name: "stop", attributes: attributes))
        }
    }

    private func clampedRGB(_ args: [Node]) -> [Double] {
        let numbers = args.prefix(3).map { max(0, min($0.numberValue ?? 0, 255)) }
        return Array(numbers)
    }

    private func invalid(_ messages: inout Messages, _ index: Int, _ filename: String?) -> Node {
        messages.error(
            "incorrect arguments given to \(rawValue)()", filename: filename, index: index)
        return .undefined
    }

}

extension Node {

    /// The raw dimension value (carto's color functions use `amount.value`
    /// directly and divide by 100 themselves; the % unit is kept).
    var numberValue: Double? {
        if case let .dimension(d) = self {
            return d.value
        }
        if case .color = self { return nil }
        if case let .quoted(s) = self { return Double(s) }
        return nil
    }

    /// carto's `number()`: % units are divided by 100 (used by rgb/hsl/hsla).
    var percentNumberValue: Double? {
        if case let .dimension(d) = self {
            return d.unit == "%" ? d.value / 100 : d.value
        }
        return numberValue
    }

    var color: Color? {
        if case let .color(c) = self { return c }
        return nil
    }

}
