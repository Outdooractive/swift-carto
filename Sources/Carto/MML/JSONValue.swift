//
//  Created by Thomas Rasch on 27.08.26.
//

import Foundation

/// A dynamic JSON value tree used by the style pipeline.
///
/// The style files are JSON5 (block and line comments, trailing commas,
/// single-quoted strings) and carry a top-level `colors` block of
/// `@xxx_color` tokens that must be inlined before the style can be served
/// or linted. `JSONDecoder` can't handle any of that, so this enum models
/// the parsed document directly.
///
/// Preserves object key order (MapLibre styles are sensitive to layer
/// order, and stable output keeps diffs reviewable).
public enum JSONValue: Sendable, Equatable {

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            true
        case let (.bool(a), .bool(b)):
            a == b
        case let (.number(a), .number(b)):
            a == b
        case let (.string(a), .string(b)):
            a == b
        case let (.array(a), .array(b)):
            a == b
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default:
            false
        }
    }

    // MARK: - Accessors

    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    public var objectValue: [(String, JSONValue)]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    /// Subscript access for object members (returns `nil` for missing keys
    /// and non-object values).
    public subscript(key: String) -> JSONValue? {
        guard case let .object(members) = self else { return nil }

        return members.first { $0.0 == key }?.1
    }

    /// Returns a copy of the object with `key` set to `value`. Non-object
    /// values are returned unchanged.
    func setting(_ key: String, to value: JSONValue) -> JSONValue {
        guard case var .object(members) = self else { return self }

        if let index = members.firstIndex(where: { $0.0 == key }) {
            members[index] = (key, value)
        }
        else {
            members.append((key, value))
        }
        return .object(members)
    }

    // MARK: - Serialization

    /// Serialize as standard JSON (2-space indentation, matching the output
    /// of the node server's `JSON.stringify(style, null, 2)`).
    func serialized() -> String {
        var output = ""
        serialize(to: &output, indent: 0)
        return output
    }

    private func serialize(to output: inout String, indent: Int) {
        let pad: String = .init(repeating: "  ", count: indent)
        let childPad: String = .init(repeating: "  ", count: indent + 1)

        switch self {
        case .null:
            output += "null"

        case let .bool(value):
            output += value ? "true" : "false"

        case let .number(value):
            output += Self.formatNumber(value)

        case let .string(value):
            output += Self.formatString(value)

        case let .array(values):
            if values.isEmpty {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, value) in values.enumerated() {
                output += childPad
                value.serialize(to: &output, indent: indent + 1)
                if index < values.count - 1 {
                    output += ","
                }
                output += "\n"
            }
            output += pad + "]"

        case let .object(members):
            if members.isEmpty {
                output += "{}"
                return
            }
            output += "{\n"
            for (index, member) in members.enumerated() {
                output += childPad + Self.formatString(member.0) + ": "
                member.1.serialize(to: &output, indent: indent + 1)
                if index < members.count - 1 {
                    output += ","
                }
                output += "\n"
            }
            output += pad + "}"
        }
    }

    /// Format a number the way `JSON.stringify` does: integers without a
    /// decimal point, everything else in its shortest round-trip form.
    static func formatNumber(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "null"
        }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    /// Escape and quote a string using JSON string rules.
    static func formatString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                }
                else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }

}

// MARK: - Convenience accessors used by the MML loader

extension JSONValue {

    public var doubleValue: Double? {
        if case let .number(value) = self {
            return value
        }
        if case let .string(value) = self {
            return Double(value)
        }
        return nil
    }

    public var intValue: Int? {
        if case let .number(value) = self {
            return Int(value)
        }
        if case let .string(value) = self {
            return Int(value)
        }
        return nil
    }

    public var objectDictionary: [String: JSONValue]? {
        guard case let .object(members) = self else { return nil }

        return Dictionary(members, uniquingKeysWith: { _, rhs in rhs })
    }

}
