//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// A font set emitted as a `<FontSet>` side effect when a text-face-name
/// value lists multiple fonts (carto's `tree.FontSet`).
struct FontSet: Equatable {
    let name: String
    let fonts: [String]
}
