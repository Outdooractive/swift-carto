//
//  Created by Thomas Rasch on 27.08.26.
//

import Foundation

/// Parses the JSON5 dialect used by the style files under
/// `<repo>/data/styles/` (the `map-styler-data` submodule).
///
/// Supported extensions over strict JSON (exactly what the style files use):
/// - `// line comments` and `/* block comments */`
/// - trailing commas in objects and arrays
/// - single-quoted strings ('case', 'boolean', ...)
/// - unquoted string literals as values are **not** supported (the style
///   files always quote values), but unquoted keys would be handled.
///
/// Numbers are parsed as `Double`; the serializer emits integers without a
/// decimal point, so the round-trip is lossless for style values.
public struct JSONParser: Sendable {

    /// A parse error with a 1-based line number (the node server reported
    /// the line in its syntax error messages, and the frontend shows it).
    struct ParseError: Error, CustomStringConvertible {
        let message: String
        let line: Int

        var description: String {
            "Error: \(message)\n\nLine: \(line)\n"
        }
    }

    private let input: [UInt8]
    private var position = 0
    /// Line number of the current position (1-based), tracked for errors.
    private var line = 1

    // MARK: - Entry point

    /// Parse `text` into a `JSONValue` tree.
    public static func parse(_ text: String) throws -> JSONValue {
        var parser: JSONParser = .init(text: text)
        let value = try parser.parseValue()
        parser.skipWhitespaceAndComments()
        guard parser.isAtEnd else {
            throw parser.error("Unexpected trailing content after JSON value")
        }

        return value
    }

    private init(text: String) {
        input = Array(text.utf8)
    }

    // MARK: - Grammar

    private mutating func parseValue() throws -> JSONValue {
        skipWhitespaceAndComments()
        guard !isAtEnd else { throw error("Unexpected end of input") }

        switch current {
        case UInt8(ascii: "{"):
            return try parseObject()

        case UInt8(ascii: "["):
            return try parseArray()

        case UInt8(ascii: "'"), UInt8(ascii: "\""):
            return try .string(parseString())

        case UInt8(ascii: "t"):
            try expectKeyword("true")
            return .bool(true)

        case UInt8(ascii: "f"):
            try expectKeyword("false")
            return .bool(false)

        case UInt8(ascii: "n"):
            try expectKeyword("null")
            return .null

        default:
            return try parseNumber()
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        try expect(UInt8(ascii: "{"))
        var members: [(String, JSONValue)] = []

        skipWhitespaceAndComments()
        if current == UInt8(ascii: "}") {
            advance()
            return .object(members)
        }

        while true {
            skipWhitespaceAndComments()
            guard !isAtEnd else { throw error("Unterminated object") }

            let key: String
            if current == UInt8(ascii: "\"") || current == UInt8(ascii: "'") {
                key = try parseString()
            }
            else {
                // Unquoted identifier key.
                var bytes: [UInt8] = []
                while !isAtEnd,
                      isIdentifierByte(current)
                {
                    bytes.append(current)
                    advance()
                }
                guard !bytes.isEmpty else {
                    throw error("Expected object key")
                }

                key = String(decoding: bytes, as: UTF8.self)
            }

            skipWhitespaceAndComments()
            try expect(UInt8(ascii: ":"))
            let value = try parseValue()
            members.append((key, value))

            skipWhitespaceAndComments()
            guard !isAtEnd else { throw error("Unterminated object") }

            if current == UInt8(ascii: ",") {
                advance()
                skipWhitespaceAndComments()
                // Trailing comma: the next byte closes the object.
                if current == UInt8(ascii: "}") {
                    advance()
                    return .object(members)
                }
                continue
            }
            if current == UInt8(ascii: "}") {
                advance()
                return .object(members)
            }
            throw error("Expected ',' or '}' in object")
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        try expect(UInt8(ascii: "["))
        var values: [JSONValue] = []

        skipWhitespaceAndComments()
        if current == UInt8(ascii: "]") {
            advance()
            return .array(values)
        }

        while true {
            let value = try parseValue()
            values.append(value)

            skipWhitespaceAndComments()
            guard !isAtEnd else { throw error("Unterminated array") }

            if current == UInt8(ascii: ",") {
                advance()
                skipWhitespaceAndComments()
                // Trailing comma.
                if current == UInt8(ascii: "]") {
                    advance()
                    return .array(values)
                }
                continue
            }
            if current == UInt8(ascii: "]") {
                advance()
                return .array(values)
            }
            throw error("Expected ',' or ']' in array")
        }
    }

    private mutating func parseString() throws -> String {
        let quote = current
        try expect(quote)
        var bytes: [UInt8] = []

        while true {
            guard !isAtEnd else { throw error("Unterminated string") }

            let byte = current

            if byte == quote {
                advance()
                return String(decoding: bytes, as: UTF8.self)
            }

            if byte == UInt8(ascii: "\\") {
                advance()
                guard !isAtEnd else { throw error("Unterminated string escape") }

                let escaped = current
                switch escaped {
                case UInt8(ascii: "\""): bytes.append(UInt8(ascii: "\""))

                case UInt8(ascii: "'"): bytes.append(UInt8(ascii: "'"))

                case UInt8(ascii: "\\"): bytes.append(UInt8(ascii: "\\"))

                case UInt8(ascii: "/"): bytes.append(UInt8(ascii: "/"))

                case UInt8(ascii: "b"): bytes.append(0x08)

                case UInt8(ascii: "f"): bytes.append(0x0C)

                case UInt8(ascii: "n"): bytes.append(0x0A)

                case UInt8(ascii: "r"): bytes.append(0x0D)

                case UInt8(ascii: "t"): bytes.append(0x09)

                case UInt8(ascii: "u"):
                    let scalar = try parseUnicodeEscape()
                    appendScalar(scalar, to: &bytes)

                default:
                    throw error("Invalid escape sequence '\\\(Character(UnicodeScalar(escaped)))'")
                }
                advance()
                continue
            }

            if byte == UInt8(ascii: "\n") {
                throw error("Unterminated string (newline in string literal)")
            }

            bytes.append(byte)
            advance()
        }
    }

    /// Parse a `\uXXXX` escape (surrogate pairs included).
    private mutating func parseUnicodeEscape() throws -> UInt32 {
        guard position + 4 <= input.count else { throw error("Invalid \\u escape") }

        var scalar: UInt32 = 0
        for _ in 0 ..< 4 {
            guard let digit = hexDigit(input[position]) else {
                throw error("Invalid \\u escape")
            }

            scalar = scalar << 4 | UInt32(digit)
            advance()
        }
        return scalar
    }

    /// Append a (possibly multi-byte) scalar value to a UTF-8 byte buffer,
    /// handling surrogate pairs for `\uD83D\uDE00`-style escapes.
    private mutating func appendScalar(_ scalar: UInt32, to bytes: inout [UInt8]) {
        var value = scalar
        // High surrogate followed by a low surrogate escape?
        if value >= 0xD800, value <= 0xDBFF,
           position + 6 <= input.count,
           input[position] == UInt8(ascii: "\\"),
           input[position + 1] == UInt8(ascii: "u"),
           let low = hexDigit(input[position + 2]),
           low >= 0xD, low <= 0xF
        {
            // Peek far enough ahead to validate the low surrogate.
            var lowValue: UInt32 = 0
            var valid = true
            for offset in 2 ... 5 {
                guard let digit = hexDigit(input[position + offset]) else {
                    valid = false
                    break
                }

                lowValue = lowValue << 4 | UInt32(digit)
            }
            if valid, lowValue >= 0xDC00, lowValue <= 0xDFFF {
                value = 0x10000 + ((value - 0xD800) << 10) + (lowValue - 0xDC00)
                advance() // backslash
                advance() // 'u'
                for _ in 0 ..< 4 {
                    advance()
                }
            }
        }
        if let unicodeScalar = Unicode.Scalar(value) {
            bytes.append(contentsOf: Array(String(unicodeScalar).utf8))
        }
        else {
            // Invalid scalar (unpaired surrogate): emit U+FFFD.
            bytes.append(contentsOf: [0xEF, 0xBF, 0xBD])
        }
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = position
        if current == UInt8(ascii: "-") || current == UInt8(ascii: "+") {
            advance()
        }
        // Infinity / NaN (JSON5)
        if !isAtEnd {
            switch current {
            case UInt8(ascii: "I"):
                try expectKeyword("Infinity")
                let negative = input[start] == UInt8(ascii: "-")
                return .number(negative ? -.infinity : .infinity)

            case UInt8(ascii: "N"):
                try expectKeyword("NaN")
                return .number(.nan)

            default:
                break
            }
        }

        var seenDot = false
        var seenExponent = false
        while !isAtEnd {
            let byte = current
            if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                advance()
            }
            else if byte == UInt8(ascii: "."), !seenDot, !seenExponent {
                seenDot = true
                advance()
            }
            else if byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E"), !seenExponent {
                seenExponent = true
                advance()
                if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") {
                    advance()
                }
            }
            else {
                break
            }
        }

        guard start != position else { throw error("Expected a value") }

        var text: String = .init(decoding: input[start ..< position], as: UTF8.self)
        // `Double` accepts "1e5" but not "1e+5" in all locales; normalize.
        if text.hasPrefix("+") { text.removeFirst() }
        guard let value = Double(text) else {
            throw error("Invalid number '\(text)'")
        }

        return .number(value)
    }

    private mutating func expectKeyword(_ keyword: String) throws {
        for byte in keyword.utf8 {
            guard !isAtEnd, current == byte else {
                throw error("Invalid literal (expected '\(keyword)')")
            }

            advance()
        }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard !isAtEnd, current == byte else {
            throw error("Expected '\(Character(UnicodeScalar(byte)))'")
        }

        advance()
    }

    // MARK: - Lexing helpers

    private var current: UInt8 {
        input[position]
    }

    private var isAtEnd: Bool {
        position >= input.count
    }

    private mutating func advance() {
        if input[position] == UInt8(ascii: "\n") {
            line += 1
        }
        position += 1
    }

    private mutating func skipWhitespaceAndComments() {
        while !isAtEnd {
            let byte = current
            switch byte {
            case 0x09, 0x0A, 0x0D, 0x20:
                advance()

            case UInt8(ascii: "/"):
                guard position + 1 < input.count else { return }

                switch input[position + 1] {
                case UInt8(ascii: "/"):
                    advance()
                    advance()
                    while !isAtEnd, current != 0x0A {
                        advance()
                    }

                case UInt8(ascii: "*"):
                    advance()
                    advance()
                    while !isAtEnd {
                        if current == UInt8(ascii: "*"),
                           position + 1 < input.count,
                           input[position + 1] == UInt8(ascii: "/")
                        {
                            advance()
                            advance()
                            break
                        }
                        advance()
                    }

                default:
                    return
                }

            default:
                return
            }
        }
    }

    private func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "_"),
             UInt8(ascii: "$"),
             UInt8(ascii: "0") ... UInt8(ascii: "9"),
             UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"):
            true
        default:
            false
        }
    }

    private func hexDigit(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): Int(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): Int(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }

    private func error(_ message: String) -> JSONParser.ParseError {
        ParseError(message: message, line: line)
    }

}

// MARK: - @color token inlining

/// Regex replacement helper: replaces every match of `pattern` in `string`
/// with the closure's return value.
private func replacingMatches(
    in string: String,
    pattern: String,
    transform: (String) -> String,
) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return string
    }

    let nsString = string as NSString
    let fullRange: NSRange = .init(location: 0, length: nsString.length)
    let matches = regex.matches(in: string, range: fullRange)

    var result = ""
    var cursor = 0
    for match in matches {
        let start = match.range.location
        let end = start + match.range.length
        if start > cursor {
            result += nsString.substring(with: NSRange(location: cursor, length: start - cursor))
        }
        result += transform(nsString.substring(with: match.range))
        cursor = end
    }
    if cursor < nsString.length {
        result += nsString.substring(from: cursor)
    }
    return result
}

extension JSONValue {

    /// Inline `@xxx_color` tokens in all string values using the given
    /// `colors` mapping. Mirrors the node server's regex replacement
    /// `(\@[-a-zA-Z0-9_]+_color)` over the serialized JSON: every string
    /// containing a `@xxx_color` token is replaced by the token's value.
    ///
    /// Returns `nil` if a referenced token has no definition (the node
    /// server left unknown tokens as-is, but a missing *definition* simply
    /// meant the literal stayed — we replicate that by leaving the string
    /// untouched when the token is unknown; the lint CLI reports it).
    func inliningColors(_ colors: [String: String]) -> JSONValue {
        switch self {
        case let .string(value):
            .string(Self.inlineColors(in: value, colors: colors))

        case let .array(values):
            .array(values.map { $0.inliningColors(colors) })

        case let .object(members):
            .object(members.map { ($0.0, $0.1.inliningColors(colors)) })

        default:
            self
        }
    }

    /// Replace `@xxx_color` tokens in a string with their values. The node
    /// implementation did a plain textual replace on the whole JSON, so a
    /// string containing several tokens (or a token plus other text) got
    /// each token substituted.
    static func inlineColors(in value: String, colors: [String: String]) -> String {
        guard value.contains("@") else { return value }

        return replacingMatches(in: value, pattern: "@[-a-zA-Z0-9_]+_color") { match in
            colors[match] ?? match
        }
    }

    /// Extract the top-level `colors` block (removing it from the value)
    /// as a `[String: String]` mapping. Returns `nil` if there is no
    /// `colors` block.
    mutating func takeColors() -> [String: String]? {
        guard case var .object(members) = self else { return nil }
        guard let index = members.firstIndex(where: { $0.0 == "colors" }) else {
            return nil
        }

        let colorsValue = members.remove(at: index).1
        self = .object(members)

        var colors: [String: String] = [:]
        if let entries = colorsValue.objectValue {
            for (key, value) in entries {
                if let string = value.stringValue {
                    colors[key] = string
                }
            }
        }
        return colors
    }

}
