//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// Evaluates nodes against variable frames (carto's `ev(env)` chain).
///
/// Frames are the variable scopes: the root frames list holds variables
/// defined at the top level of stylesheets; nested rulesets push their own.
struct Evaluator {

    var env: ParserEnv
    /// Frames of variable name → Rule, innermost last (carto uses unshift
    /// so index 0 is innermost; we append and search backwards).
    var frames: [[String: Rule]] = []
    /// Side effects collected during evaluation (FontSets).
    var fontSets: [FontSet] = []
    var fontMap: [String: String] = [:]
    var messages: Messages

    // MARK: - Frames

    mutating func pushFrame(_ frame: [String: Rule]) {
        frames.append(frame)
    }

    mutating func popFrame() {
        if !frames.isEmpty {
            frames.removeLast()
        }
    }

    // MARK: - Node evaluation

    mutating func evaluate(_ node: Node) -> Node {
        switch node {
        case let .dimension(dimension):
            return evaluateDimension(dimension)

        case .color:
            return node

        case .field, .imageFilter, .keyword, .literal, .quoted, .tag, .url:
            return node

        case let .variable(name, index, filename):
            return resolveVariable(name: name, index: index, filename: filename)

        case let .operation(operation):
            return evaluateOperation(operation)

        case let .expression(nodes):
            if nodes.count > 1 {
                return .expression(nodes.map { evaluate($0) })
            }
            else if let first = nodes.first {
                return evaluate(first)
            }
            return node

        case let .value(value):
            return evaluateValue(value)

        case let .call(call):
            return evaluateCall(call)

        case .undefined:
            return node
        }
    }

    mutating func evaluateValue(_ value: Value) -> Node {
        if value.values.count == 1, let first = value.values.first {
            return evaluate(first)
        }
        return .value(Value(values: value.values.map { evaluate($0) }))
    }

    private mutating func evaluateDimension(_ dimension: Dimension) -> Node {
        var dimension = dimension
        if let unit = dimension.unit, !Dimension.allUnits.contains(unit) {
            messages.error("Invalid unit: '\(unit)'", filename: env.filename)
            return .undefined
        }

        // normalize units which are not px or %
        if let unit = dimension.unit, Dimension.physicalUnits.contains(unit) {
            guard let density = Dimension.densities[unit] else {
                return .undefined
            }

            dimension.value = (dimension.value / density) * env.ppi
            dimension.unit = "px"
        }
        return .dimension(dimension)
    }

    private mutating func resolveVariable(name: String, index: Int, filename: String?) -> Node {
        for frame in frames.reversed() {
            if let rule = frame[name] {
                return evaluateValue(rule.value)
            }
        }

        messages.error("variable \(name) is undefined", filename: filename, index: index)
        return .undefined
    }

    private mutating func evaluateOperation(_ operation: Operation) -> Node {
        let lhs = evaluate(operation.lhs)
        let rhs = evaluate(operation.rhs)

        if lhs.isUndefined || rhs.isUndefined {
            return .undefined
        }

        let op = operation.op
        var lhsEvaluated = lhs
        var rhsEvaluated = rhs
        if case .dimension = lhs, case .color = rhs {
            if op == .multiply || op == .add {
                swap(&lhsEvaluated, &rhsEvaluated)
            }
            else {
                messages.error(
                    "Can't substract or divide a color from a number", filename: env.filename)
                return .undefined
            }
        }

        if case .quoted = lhsEvaluated, case .quoted = rhsEvaluated, op != .add {
            messages.error("Can't subtract, divide, or multiply strings.", filename: env.filename)
            return .undefined
        }

        // Fields, literals, dimensions, and quoted strings can be combined
        // into literal fragments (for mapnik expressions).
        if lhsEvaluated.isFieldLike || rhsEvaluated.isFieldLike {
            if lhsEvaluated.isColor || rhsEvaluated.isColor {
                messages.error(
                    "Can't subtract, divide, or multiply colors in expressions.",
                    filename: env.filename)
                return .undefined
            }
            return .literal(
                lhsEvaluated.expressionString(quoted: true) + op.rawValue
                    + rhsEvaluated.expressionString(quoted: true))
        }

        switch (lhsEvaluated, rhsEvaluated) {
        case let (.dimension(d1), .dimension(d2)):
            return operate(d1, d2, op)

        case let (.dimension(d1), .color(c)):
            if op == .multiply || op == .add {
                if let result = c.operate(op, .dimension(d1)) {
                    return .color(result)
                }
            }
            messages.error("Cannot do math with type color.", filename: env.filename)
            return .undefined

        case let (.color(c), .dimension):
            if let result = c.operate(op, rhsEvaluated) {
                return .color(result)
            }
            messages.error("Cannot do math with type color.", filename: env.filename)
            return .undefined

        case let (.color(c1), .color(c2)):
            if let result = c1.operate(op, .color(c2)) {
                return .color(result)
            }
            return .undefined

        case let (.quoted(s1), .quoted(s2)):
            if op == .add {
                return .quoted(s1 + s2)
            }
            return .undefined

        case let (.keyword(s1), .quoted(s2)) where op == .add:
            return .literal(s1 + s2)

        case let (.quoted(s1), .keyword(s2)) where op == .add:
            return .quoted(s1 + s2)

        case let (.keyword(s1), .keyword(s2)) where op == .add:
            return .keyword(s1 + s2)

        case (.dimension, .quoted) where op == .add:
            return .literal(
                lhsEvaluated.expressionString(quoted: true) + op.rawValue
                    + rhsEvaluated.expressionString(quoted: true))

        case (.quoted, .dimension) where op == .add:
            return .literal(
                lhsEvaluated.expressionString(quoted: true) + op.rawValue
                    + rhsEvaluated.expressionString(quoted: true))

        default:
            messages.error("Cannot do math with type \(lhsEvaluated.typeName).", filename: env.filename)
            return .undefined
        }
    }

    private func operate(_ a: Dimension, _ b: Dimension, _ op: Operation.Op) -> Node {
        _ = messages
        if a.unit == "%", b.unit != "%" {
            messages.error("If two operands differ, the first must not be %", filename: env.filename)
            return .undefined
        }

        if a.unit != "%", b.unit == "%" {
            if op == .multiply || op == .divide || op == .modulo {
                messages.error(
                    "Percent values can only be added or subtracted from other values",
                    filename: env.filename)
                return .undefined
            }
            return .dimension(
                Dimension(
                    value: math(op, a.value, a.value * b.value * 0.01),
                    unit: a.unit))
        }

        return .dimension(Dimension(value: math(op, a.value, b.value), unit: a.unit ?? b.unit))
    }

    private func math(_ op: Operation.Op, _ a: Double, _ b: Double) -> Double {
        switch op {
        case .add: a + b
        case .subtract: a - b
        case .multiply: a * b
        case .modulo: a.truncatingRemainder(dividingBy: b)
        case .divide: a / b
        }
    }

    // MARK: - Function calls

    private mutating func evaluateCall(_ call: Call) -> Node {
        let args = call.args.map { evaluate($0) }
        for arg in args where arg.isUndefined {
            return .undefined
        }

        if let function = BuiltinFunction(rawValue: call.name) {
            return function.call(args, &messages, call.index, env.filename)
        }

        // Reference-defined functions (geometry transforms etc.) are passed
        // through as serialized calls.
        if Reference.functions[call.name] != nil {
            return .call(Call(name: call.name, args: args, index: call.index, filename: call.filename))
        }

        messages.error(
            "unknown function \(call.name)()", filename: call.filename, index: call.index)
        return .undefined
    }

}

extension Node {

    var isFieldLike: Bool {
        switch self {
        case .field, .literal:
            true
        default:
            false
        }
    }

    var isColor: Bool {
        if case .color = self {
            return true
        }
        return false
    }

    var typeName: String {
        switch self {
        case .dimension: "float"
        case .color: "color"
        case .quoted: "string"
        case let .keyword(v): v == "transparent" ? "color" : (v == "true" || v == "false" ? "boolean" : "keyword")
        case .field: "field"
        case .literal: "field"
        case .url: "uri"
        case .variable: "variable"
        case .operation: "operation"
        case .expression: "expression"
        case .value: "value"
        case .call: "call"
        case .tag: "tag"
        case .imageFilter: "imagefilter"
        case .undefined: "undefined"
        }
    }

    /// String form used when combining fields into mapnik expression
    /// fragments (carto's `Literal` concatenation). Quoted strings keep
    /// single quotes in the fragment.
    func expressionString(quoted: Bool = false) -> String {
        switch self {
        case let .quoted(s):
            if quoted {
                return "'" + s + "'"
            }
            return s

        default:
            return idString
        }
    }

}

/// Number formatting matching JavaScript's `Number.toString()` for the
/// values carto emits: integers without decimals, shortest round-trip
/// otherwise.
func formatNumber(_ value: Double) -> String {
    if value.isNaN {
        return "NaN"
    }
    if value.isInfinite {
        return value > 0 ? "Infinity" : "-Infinity"
    }
    if value == value.rounded() && abs(value) < 1e21 {
        // JS prints integers without decimal point
        if abs(value) < 9_007_199_254_740_992 {
            return String(Int(value))
        }
    }
    // JS switches to exponent notation for abs < 1e-6 and >= 1e21.
    let absolute = abs(value)
    if absolute != 0, absolute < 1e-6 {
        // JS form: 3.6e-7 (no plus sign, no leading zeros in exponent)
        var exponent = 0
        var mantissa = absolute
        while mantissa < 1 {
            mantissa *= 10
            exponent -= 1
        }
        while mantissa >= 10 {
            mantissa /= 10
            exponent += 1
        }
        let mantissaText = mantissa == mantissa.rounded()
            ? String(Int(mantissa)) : String(mantissa)
        return (value < 0 ? "-" : "") + mantissaText + "e"
            + (exponent < 0 ? "-" : "+") + String(abs(exponent))
    }
    // Shortest round-trip representation, like JS default (decimal for
    // 1e-6 <= abs < 1e21). Expand Swift's exponent form (e.g. "3.6e-05")
    // into JS's decimal form.
    var output: String = .init(value)
    if output.contains("e") || output.contains("E") {
        let lower = output.lowercased()
        let eIndex = lower.firstIndex(of: "e")!
        let mantissaText: String = .init(output[..<eIndex])
        let exponent = Int(output[output.index(after: eIndex)...]) ?? 0
        let negativeMantissa = mantissaText.hasPrefix("-")
        let unsigned = negativeMantissa ? String(mantissaText.dropFirst()) : mantissaText
        var digits = unsigned.replacingOccurrences(of: ".", with: "")
        var decimalPosition: Int = if let dotIndex = unsigned.firstIndex(of: ".") {
            unsigned.distance(from: unsigned.startIndex, to: dotIndex)
        }
        else {
            unsigned.count
        }
        decimalPosition += exponent
        while decimalPosition > digits.count {
            digits += "0"
        }
        while decimalPosition <= 0 {
            digits = "0" + digits
            decimalPosition += 1
        }
        let integerPart: String = .init(digits.prefix(decimalPosition))
        let fractionPart = decimalPosition < digits.count
            ? "." + String(digits.dropFirst(decimalPosition)) : ""
        return (value < 0 ? "-" : "") + integerPart + fractionPart
    }
    if output.hasSuffix(".0") {
        output.removeLast(2)
    }
    return output
}
