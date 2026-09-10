//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// Evaluated zoom bitmask helpers (carto's `tree.Zoom`).
enum Zoom {

    static let maxZoom = 25

    /// Bitmask covering zoom levels 0–maxZoom.
    static let all: Int = (1 << (maxZoom + 1)) - 1

    /// Scale denominators at each zoom boundary (carto's `Zoom.ranges`).
    static let ranges: [Int: Double] = [
        0: 1_000_000_000, 1: 500_000_000, 2: 200_000_000, 3: 100_000_000,
        4: 50_000_000, 5: 25_000_000, 6: 12_500_000, 7: 6_500_000,
        8: 3_000_000, 9: 1_500_000, 10: 750_000, 11: 400_000,
        12: 200_000, 13: 100_000, 14: 50000, 15: 25000,
        16: 12500, 17: 5000, 18: 2500, 19: 1500,
        20: 750, 21: 500, 22: 250, 23: 100,
        24: 50, 25: 25, 26: 12.5,
    ]

    /// Evaluate a zoom condition to a bitmask (carto's `tree.Zoom.ev`):
    /// the value is evaluated against the variable frames first, so
    /// `[zoom >= @min_zoom]` works with variable (and computed) values.
    static func evaluate(
        op: Filter.Op,
        value: Node,
        evaluator: inout Evaluator,
        messages: inout Messages,
        index: Int,
        filename: String?,
    ) -> Int {
        let evaluated = evaluator.evaluate(value)
        if evaluated.isUndefined {
            // resolveVariable already reported the error.
            return 0
        }
        let stringValue: String = switch evaluated {
        case let .dimension(d):
            formatNumber(d.value)
        default:
            evaluated.idString
        }
        // carto uses parseInt(..., 10): truncation, leading-number prefix.
        let zoom = Self.parseInt(stringValue) ?? -1

        if zoom > maxZoom || zoom < 0 {
            messages.error(
                "Only zoom levels between 0 and \(maxZoom) supported.", filename: filename, index: index)
            return 0
        }

        switch op {
        case .eq:
            return 1 << zoom
        case .gt:
            return rangeMask(start: zoom + 1, end: maxZoom)
        case .gte:
            return rangeMask(start: zoom, end: maxZoom)
        case .lt:
            return rangeMask(start: 0, end: zoom - 1)
        case .lte:
            return rangeMask(start: 0, end: zoom)
        case .neq:
            // carto's Zoom.ev has no case for '!=' → full range.
            return rangeMask(start: 0, end: maxZoom)
        case .match:
            return 0
        }
    }

    static func rangeMask(start: Int, end: Int) -> Int {
        var zoom = 0
        for i in 0 ... maxZoom where i >= start && i <= end {
            zoom |= (1 << i)
        }
        return zoom
    }

    /// JavaScript `parseInt(string, 10)`: truncates at the first non-digit
    /// (no rounding, no exponent handling), returns nil for NaN.
    static func parseInt(_ string: String) -> Int? {
        var characters = Substring(string).drop { $0 == " " || $0 == "\t" || $0 == "\n" }
        // Optional sign.
        var negative = false
        if characters.first == "-" || characters.first == "+" {
            negative = characters.first == "-"
            characters = characters.dropFirst()
        }
        var value = 0
        var count = 0
        for c in characters {
            guard c.isASCII, let digit = c.wholeNumberValue, digit <= 9 else { break }

            value = value * 10 + digit
            count += 1
        }
        if count == 0 {
            return nil
        }
        return negative ? -value : value
    }

    /// Scale-denominator conditions for a zoom bitmask (carto's
    /// `Zoom.toObject`): `MaxScaleDenominator` for the start, `Min` for the
    /// end, only when the mask is not "all".
    static func scaleDenominators(zoom: Int) -> [(String, String)] {
        var conditions: [(String, String)] = []
        if zoom != all {
            var start: Int?
            var end: Int?
            for i in 0 ... maxZoom where zoom & (1 << i) != 0 {
                if start == nil {
                    start = i
                }
                end = i
            }
            if let start, start > 0 {
                conditions.append(("MaxScaleDenominator", formatNumber(ranges[start] ?? 0)))
            }
            if let end, end < maxZoom {
                conditions.append(("MinScaleDenominator", formatNumber(ranges[end + 1] ?? 0)))
            }
        }
        return conditions
    }

}
