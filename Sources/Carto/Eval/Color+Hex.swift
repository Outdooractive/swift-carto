//
//  Created by Thomas Rasch, 2026.
//

import Foundation

extension Color {

    /// Parse a 3- or 6-digit hex color string (without `#`) to RGB 0–255.
    static func hexToRGB(_ hex: String) -> [Double] {
        var value = hex.lowercased()
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            return [0, 0, 0]
        }

        return [
            Double((rgb >> 16) & 0xFF), Double((rgb >> 8) & 0xFF), Double(rgb & 0xFF),
        ]
    }

}
