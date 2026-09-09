//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// Runtime values in evaluated rules. Mirrors carto's tree entities.
indirect enum Node {

    case dimension(Dimension)
    case color(Color)
    case quoted(String)
    case keyword(String)
    case field(String)
    case literal(String)
    case url(String)
    case variable(name: String, index: Int, filename: String?)
    case operation(Operation)
    case expression([Node])
    case value(Value)
    case call(Call)
    case tag(TagNode)
    case imageFilter(name: String, args: [Node])
    case undefined

    var isUndefined: Bool {
        if case .undefined = self { return true }
        return false
    }

}

/// A number with an optional unit.
struct Dimension {

    var value: Double
    var unit: String?

    static let physicalUnits: Set<String> = ["m", "cm", "in", "mm", "pt", "pc"]
    static let allUnits: Set<String> = ["m", "cm", "in", "mm", "pt", "pc", "px", "%"]
    /// densities: how many of each unit per inch.
    static let densities: [String: Double] = [
        "m": 0.0254, "mm": 25.4, "cm": 2.54, "pt": 72, "pc": 6,
    ]

}

/// A function call with evaluated (or unevaluated) arguments.
struct Operation {

    enum Op: String {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        case modulo = "%"
    }

    var op: Op
    var lhs: Node
    var rhs: Node

}

/// A function call like `rgb(255, 0, 255)`.
struct Call {

    var name: String
    var args: [Node]
    var index: Int
    var filename: String?

}

/// A serialized tag produced by `stop()` (carto's tag objects from
/// `functions.js`).
struct TagNode {

    var name: String
    /// Ordered (name, value) attributes.
    var attributes: [(String, String)]

}
