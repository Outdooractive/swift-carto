//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// Errors thrown by the Carto pipeline.
public struct CartoError: Error, Sendable, CustomStringConvertible {

    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }

}

/// A compile message (error or warning) produced while rendering, mirroring
/// carto's `env.msg` entries.
public struct Message: Sendable, Equatable, CustomStringConvertible {

    public enum Kind: String, Sendable {
        case error
        case warning
    }

    public let kind: Kind
    public let message: String
    public let filename: String?
    public let line: Int
    public let column: Int

    public init(
        kind: Kind,
        message: String,
        filename: String? = nil,
        line: Int = -1,
        column: Int = -1,
    ) {
        self.kind = kind
        self.message = message
        self.filename = filename
        self.line = line
        self.column = column
    }

    public var description: String {
        var output = "\(kind): "
        if let filename {
            output += line >= 0 ? "\(filename):\(line):\(column) " : "\(filename) "
        }
        output += message
        return output
    }

}

/// Collects errors and warnings during a render pass.
final class Messages: @unchecked Sendable {

    private(set) var items: [Message] = []

    func add(_ message: Message) {
        // Deduplicate identical messages (carto does the same).
        if items.contains(message) {
            return
        }
        items.append(message)
    }

    func error(
        _ message: String,
        filename: String? = nil,
        index: Int? = nil,
        input: String? = nil,
    ) {
        let (line, column) = Self.lineColumn(input: input, index: index)
        add(Message(kind: .error, message: message, filename: filename, line: line, column: column))
    }

    func warning(
        _ message: String,
        filename: String? = nil,
        index: Int? = nil,
        input: String? = nil,
    ) {
        let (line, column) = Self.lineColumn(input: input, index: index)
        add(Message(kind: .warning, message: message, filename: filename, line: line, column: column))
    }

    var hasErrors: Bool {
        items.contains { $0.kind == .error }
    }

    static func lineColumn(
        input: String?,
        index: Int?,
    ) -> (Int, Int) {
        guard let input, let index, index >= 0, index <= input.count else { return (-1, -1) }

        let prefix = input[input.startIndex ..< input.index(input.startIndex, offsetBy: index)]
        let line = prefix.count(where: { $0 == "\n" }) + 1
        let column = index - (prefix.lastIndex(of: "\n").map {
            input.distance(from: input.startIndex, to: $0) + 1
        } ?? 0)
        return (line, column)
    }

}
