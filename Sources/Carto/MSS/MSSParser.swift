//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// Parser environment, threaded through parsing and evaluation. Mirrors the
/// mutable parts of carto's `env`.
struct ParserEnv {

    /// ppi for unit conversion.
    var ppi: Double = 90.714
    var filename: String?
    /// Source text per filename, for error line/column computation.
    var inputs: [String: String] = [:]

    /// - Parameters:
    ///   - ppi: Pixels per inch for physical-unit conversion.
    ///   - filename: The stylesheet filename, used for error messages.
    init(ppi: Double = 90.714, filename: String? = nil) {
        self.ppi = ppi
        self.filename = filename
    }

}

/// Parses a CartoCSS (`.mss`) document into an AST.
///
/// This is a faithful port of carto's chunk-based recursive-descent parser
/// (`lib/carto/parser.js`): the input is split into chunks at top-level `}`
/// `` boundaries (keeping strings, comments and `url(...)` groups intact),
/// then the chunks are consumed with backtracking.
struct MSSParser {

    private let input: [Character]
    private var i = 0
    private var j = 0
    private var chunks: [String] = []
    private var memo = 0
    private var env: ParserEnv

    /// Parse a stylesheet into a root ruleset. The env is copied in; callers
    /// keep their own copy (parser only needs `filename`).
    static func parse(_ text: String, env: ParserEnv) throws -> MSSRoot {
        var parser: MSSParser = .init(text: text, env: env)
        return try parser.parseRoot()
    }

    private init(text: String, env: ParserEnv) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        input = Array(normalized)
        self.env = env
    }

    // MARK: - Chunking

    /// Split the input into chunks at top-level `}` boundaries, keeping
    /// strings, comments, and `url(...)` parameter groups together.
    private mutating func makeChunks() throws {
        var chunks: [[String]] = [[]]
        var chunk = 0
        var level = 0
        var inParam = false

        var index = 0
        let chars = input

        while index < chars.count {
            let skip = skipSpanEnd(from: index)
            if skip > index {
                chunks[chunk].append(String(chars[index ..< skip]))
                index = skip
            }
            guard index < chars.count else { break }

            let c = chars[index]

            if c == "\"" || c == "'" || c == "`" {
                if let end = stringEnd(from: index) {
                    chunks[chunk].append(String(chars[index ... end]))
                    index = end + 1
                    continue
                }
            }

            if !inParam, c == "/" {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                if next == "/" {
                    if let end = lineCommentEnd(from: index) {
                        chunks[chunk].append(String(chars[index ... end]))
                        index = end + 1
                        continue
                    }
                }
                else if next == "*" {
                    if let end = blockCommentEnd(from: index) {
                        chunks[chunk].append(String(chars[index ... end]))
                        index = end + 1
                        continue
                    }
                }
            }

            switch c {
            case "{":
                if !inParam {
                    level += 1
                }
                else {
                    inParam = false
                }
                chunks[chunk].append("{")

            case "}":
                if !inParam {
                    level -= 1
                    chunks[chunk].append("}")
                    chunk += 1
                    chunks.append([])
                }
                else {
                    inParam = false
                    chunks[chunk].append("}")
                }

            case "(":
                if !inParam {
                    inParam = true
                }
                else {
                    inParam = false
                }
                chunks[chunk].append("(")

            case ")":
                if inParam {
                    inParam = false
                }
                chunks[chunk].append(")")

            default:
                chunks[chunk].append(String(c))
            }

            index += 1
        }

        if level != 0 {
            let message = (level > 0) ? "missing closing `}`" : "missing opening `{`"
            throw CartoError("\(message) in \(env.filename ?? "input")")
        }

        self.chunks = chunks.map { $0.joined() }
    }

    /// The `skip` run of carto's chunker: everything up to the next
    /// delimiter (quotes/braces/slashes/parens/backslash/`@{`).
    private func skipSpanEnd(from index: Int) -> Int {
        var end = index
        while end < input.count {
            let c = input[end]
            switch c {
            case "'", "(", ")", "{", "}", "/", "\"", "\\", "`":
                return end == index ? index : end
            default:
                end += 1
            }
        }
        return end
    }

    private func stringEnd(from index: Int) -> Int? {
        let quote = input[index]
        var end = index + 1
        while end < input.count {
            let c = input[end]
            if c == "\\" {
                end += 2
                continue
            }
            if c == quote {
                return end
            }
            if c == "\n" || c == "\r" { return nil }
            end += 1
        }
        return nil
    }

    private func lineCommentEnd(from index: Int) -> Int? {
        var end = index + 2
        while end < input.count, input[end] != "\n" {
            end += 1
        }
        return end - 1
    }

    private func blockCommentEnd(from index: Int) -> Int? {
        var end = index + 2
        while end + 1 < input.count {
            if input[end] == "*", input[end + 1] == "/" {
                return end + 1
            }
            end += 1
        }
        return nil
    }

    // MARK: - Character helpers

    /// Consume a literal character if it matches, then skip whitespace.
    private mutating func switchToken(_ tok: Character) -> String? {
        if i < input.count, input[i] == tok {
            i += 1
            skipWhitespace()
            return String(tok)
        }
        return nil
    }

    private mutating func skipWhitespace() {
        while i < input.count, input[i] == " " || input[i] == "\n" || input[i] == "\t" {
            i += 1
        }
    }

    private func isNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_"
    }

    private func isDigit(_ c: Character) -> Bool {
        c.isNumber
    }

    // MARK: - Root

    private mutating func parseRoot() throws -> MSSRoot {
        i = 0
        j = 0
        try makeChunks()

        var nodes: [MSSNode] = []
        while true {
            if i < input.count, input[i] == "}" { break }
            if let node = try parseRule() {
                nodes.append(node)
                continue
            }
            if let ruleset = try parseRuleset() {
                nodes.append(.ruleset(ruleset))
                continue
            }
            if let comment = parseComment() {
                nodes.append(.comment(comment))
                continue
            }
            if matchWhitespace() {
                continue
            }
            if let invalid = parseInvalid() {
                nodes.append(.invalid(invalid))
                continue
            }
            break
        }
        return MSSRoot(nodes: nodes)
    }

    private mutating func matchWhitespace() -> Bool {
        var any = false
        while i < input.count, input[i] == " " || input[i] == "\n" || input[i] == "\t" {
            i += 1
            any = true
        }
        return any
    }

    // MARK: - Comments / invalid

    private mutating func parseComment() -> CommentNode? {
        guard i + 1 < input.count, input[i] == "/" else { return nil }

        if input[i + 1] == "/" {
            var end = i + 2
            while end < input.count, input[end] != "\n" {
                end += 1
            }
            let text: String = .init(input[(i + 2) ..< end])
            i = min(end, input.count)
            skipWhitespace()
            return CommentNode(text: text, silent: true)
        }

        if input[i + 1] == "*" {
            var end = i + 2
            while end + 1 < input.count {
                if input[end] == "*", input[end + 1] == "/" {
                    let text: String = .init(input[i ... end + 1])
                    i = end + 2
                    if i < input.count, input[i] == "\n" { i += 1 }
                    skipWhitespace()
                    return CommentNode(text: text, silent: false)
                }
                end += 1
            }
            return nil
        }

        return nil
    }

    /// Error recovery: consume up to a semicolon or line break.
    private mutating func parseInvalid() -> InvalidNode? {
        let start = i
        var end = i
        while end < input.count, input[end] != ";", input[end] != "\n" {
            end += 1
        }
        guard end < input.count else { return nil }

        let text: String = .init(input[start ..< min(end + 1, input.count)])
        i = end + 1
        skipWhitespace()
        return InvalidNode(text: text, index: start)
    }

    // MARK: - Rulesets

    private mutating func parseRuleset() throws -> RulesetNode? {
        let savedI = i
        let savedJ = j
        let savedChunks = chunks

        var selectors: [Selector] = []
        while let selector = try parseSelector() {
            selectors.append(selector)
            skipWhitespace()
            // comments between selectors
            while parseComment() != nil {
                skipWhitespace()
            }
            if switchToken(",") == nil { break }
            skipWhitespace()
            while parseComment() != nil {
                skipWhitespace()
            }
        }

        guard !selectors.isEmpty, let content = try parseBlock() else {
            // Backtrack
            i = savedI
            j = savedJ
            chunks = savedChunks
            return nil
        }

        var isMap = false
        if selectors.count == 1, let first = selectors[0].elements.first,
           first.value == "Map"
        {
            isMap = true
        }
        return RulesetNode(selectors: selectors, isMap: isMap, content: content)
    }

    private mutating func parseBlock() throws -> [MSSNode]? {
        guard switchToken("{") != nil else { return nil }

        var content: [MSSNode] = []
        while true {
            if i < input.count, input[i] == "}" { break }

            if let node = try parseRule() {
                content.append(node)
                continue
            }
            if let ruleset = try parseRuleset() {
                content.append(.ruleset(ruleset))
                continue
            }
            if let comment = parseComment() {
                content.append(.comment(comment))
                continue
            }
            if matchWhitespace() {
                continue
            }
            if let invalid = parseInvalid() {
                content.append(.invalid(invalid))
                continue
            }
            break
        }
        guard switchToken("}") != nil else { return nil }

        return content
    }

    private mutating func parseSelector() throws -> Selector? {
        var elements: [Element] = []
        var filters: FilterSet = .init()
        var zooms: [ZoomNode] = []
        var attachment: String?
        var segments = 0
        var conditions = 0

        while true {
            if let element = parseElement() {
                elements.append(element)
                segments += 1
            }
            else if let zoom = try parseZoom() {
                zooms.append(zoom)
                conditions += 1
                segments += 1
            }
            else if let filter = try parseFilter() {
                if let error = filters.add(filter) {
                    throw CartoError("\(error) in \(env.filename ?? "input")")
                }
                conditions += 1
                segments += 1
            }
            else if attachment == nil, let attachmentName = parseAttachment() {
                attachment = attachmentName
                segments += 1
            }
            else {
                break
            }

            if i < input.count {
                let c = input[i]
                if c == "{" || c == "}" || c == ";" || c == "," { break }
            }
        }

        if segments > 0 {
            return Selector(
                elements: elements, filters: filters, zoom: Zoom.all, zooms: zooms,
                attachment: attachment, conditions: conditions, index: memo)
        }
        return nil
    }

    private mutating func parseElement() -> Element? {
        let start = i
        guard i < input.count else { return nil }

        let c = input[i]
        if c == "#" || c == "." {
            var end = i + 1
            while end < input.count, isNameChar(input[end]) {
                end += 1
            }
            if end > i + 1 {
                let value: String = .init(input[start ..< end])
                i = end
                skipWhitespace()
                return Element(value: value)
            }
            return nil
        }
        if c == "*" {
            i += 1
            skipWhitespace()
            return Element(value: "*")
        }
        if i + 3 <= input.count, input[i] == "M", input[i + 1] == "a", input[i + 2] == "p" {
            let after = i + 3
            if after == input.count || !isNameChar(input[after]) {
                i = after
                skipWhitespace()
                return Element(value: "Map")
            }
        }
        return nil
    }

    private mutating func parseAttachment() -> String? {
        // `::name` (optionally `name/subname`)
        guard i + 1 < input.count, input[i] == ":", input[i + 1] == ":" else { return nil }

        var end = i + 2
        var nameLength = 0
        while end < input.count, isNameChar(input[end]) {
            end += 1
            nameLength += 1
        }
        if nameLength == 0 { return nil }
        // Optional `/second`
        if end < input.count, input[end] == "/" {
            var subEnd = end + 1
            var subLength = 0
            while subEnd < input.count, isNameChar(input[subEnd]) {
                subEnd += 1
                subLength += 1
            }
            if subLength > 0 {
                let value: String = .init(input[i ..< subEnd])
                i = subEnd
                skipWhitespace()
                return String(value.dropFirst(2))
            }
        }
        if nameLength > 0 {
            let value: String = .init(input[i ..< end])
            i = end
            skipWhitespace()
            return String(value.dropFirst(2))
        }
        return nil
    }

    private mutating func parseZoom() throws -> ZoomNode? {
        let savedI = i
        let savedMemo = memo

        // `[` + optional space + `zoom`
        guard switchToken("[") != nil else { return nil }

        skipWhitespace()
        guard matchLiteral("zoom") else {
            i = savedI
            return nil
        }
        guard let op = parseComparison() else {
            i = savedI
            return nil
        }

        skipWhitespace()
        // value: variable or dimension
        let value: Node
        if let variable = parseVariableEntity() {
            value = variable
        }
        else if let dimension = parseDimensionEntity() {
            value = dimension
        }
        else {
            i = savedI
            return nil
        }
        skipWhitespace()
        guard switchToken("]") != nil else {
            i = savedI
            return nil
        }

        memo = savedMemo
        return ZoomNode(op: op, value: value, index: savedMemo)
    }

    private mutating func matchLiteral(_ literal: String) -> Bool {
        let literalChars: Array = .init(literal)
        guard i + literalChars.count <= input.count else { return false }

        for (offset, c) in literalChars.enumerated() {
            if input[i + offset] != c { return false }
        }
        i += literalChars.count
        skipWhitespace()
        return true
    }

    private mutating func parseComparison() -> Filter.Op? {
        // Two-char operators first.
        if i + 1 < input.count {
            let two: String = .init(input[i ... i + 1])
            switch two {
            case "=~": i += 2; skipWhitespace(); return .match
            case "!=": i += 2; skipWhitespace(); return .neq
            case "<=": i += 2; skipWhitespace(); return .lte
            case ">=": i += 2; skipWhitespace(); return .gte
            default: break
            }
        }
        guard i < input.count else { return nil }

        switch input[i] {
        case "=": i += 1; skipWhitespace(); return .eq
        case "<": i += 1; skipWhitespace(); return .lt
        case ">": i += 1; skipWhitespace(); return .gt
        default: return nil
        }
    }

    // MARK: - Filters

    private mutating func parseFilter() throws -> Filter? {
        let savedI = i
        let savedMemo = memo

        guard switchToken("[") != nil else { return nil }

        skipWhitespace()

        var key: Node?
        // key: plain identifier (incl. underscore, carto: [a-zA-Z0-9\-_]+)
        // | quoted | expression | variable | keyword | field
        if let field = parseFieldEntity() {
            key = field
        }
        else if let identifier = parseFilterIdentifier() {
            key = .field(identifier)
        }
        else if let variable = parseVariableEntity() {
            key = variable
        }
        else if let expression = try parseExpression() {
            key = expression
        }
        else if let quoted = parseQuotedEntity() {
            key = .quoted(quoted)
        }

        guard var keyNode = key else {
            i = savedI
            return nil
        }

        // Quoted keys become fields (carto does this conversion).
        if case let .quoted(content) = keyNode {
            keyNode = .field(content)
        }

        skipWhitespace()
        guard let op = parseComparison() else {
            i = savedI
            memo = savedMemo
            return nil
        }

        skipWhitespace()

        let value: Node
        if let expression = try parseExpression() {
            value = expression
        }
        else if let quoted = parseQuotedEntity() {
            value = .quoted(quoted)
        }
        else if let variable = parseVariableEntity() {
            value = variable
        }
        else if let dimension = parseDimensionEntity() {
            value = dimension
        }
        else if let keyword = parseKeywordEntity() {
            value = .keyword(keyword)
        }
        else if let field = parseFieldEntity() {
            value = field
        }
        else {
            i = savedI
            memo = savedMemo
            return nil
        }

        skipWhitespace()
        guard switchToken("]") != nil else {
            throw CartoError("Missing closing ] of filter. in \(env.filename ?? "input")")
        }

        return Filter(key: keyNode, op: op, value: value, index: savedMemo, filename: env.filename)
    }

    /// A filter key: `[a-zA-Z0-9\-_]+` (carto's filter key regex).
    private mutating func parseFilterIdentifier() -> String? {
        guard i < input.count else { return nil }

        var end = i
        while end < input.count, isNameChar(input[end]) {
            end += 1
        }
        guard end > i else { return nil }

        let value: String = .init(input[i ..< end])
        i = end
        return value
    }

    // MARK: - Entities

    private mutating func parseQuotedEntity() -> String? {
        guard i < input.count, input[i] == "\"" || input[i] == "'" else { return nil }

        let quote = input[i]
        var end = i + 1
        var content = ""
        while end < input.count {
            let c = input[end]
            if c == "\\", end + 1 < input.count {
                // carto keeps escapes raw (the Quoted value stores the
                // backslash and the escaped character).
                content.append("\\")
                content.append(input[end + 1])
                end += 2
                continue
            }
            if c == quote {
                i = end + 1
                skipWhitespace()
                return content
            }
            if c == "\n" { break }
            content.append(c)
            end += 1
        }
        return nil
    }

    private mutating func parseFieldEntity() -> Node? {
        guard i < input.count, input[i] == "[" else { return nil }

        var end = i + 1
        while end < input.count, input[end] != "]" {
            end += 1
        }
        guard end < input.count, end > i + 1 else { return nil }

        let name: String = .init(input[(i + 1) ..< end])
        i = end + 1
        skipWhitespace()
        return .field(name)
    }

    private mutating func parseVariableEntity() -> Node? {
        guard i < input.count, input[i] == "@" else { return nil }

        var end = i + 1
        while end < input.count, isNameChar(input[end]) {
            end += 1
        }
        guard end > i + 1 else { return nil }

        let name: String = .init(input[i ..< end])
        i = end
        skipWhitespace()
        return .variable(name: name, index: i, filename: env.filename)
    }

    /// A variable definition position: `@name:` — returns the name.
    private mutating func parseVariableDefinition() -> String? {
        let savedI = i
        guard i < input.count, input[i] == "@" else { return nil }

        var end = i + 1
        while end < input.count, isNameChar(input[end]) {
            end += 1
        }
        guard end > i + 1 else { return nil }

        let name: String = .init(input[i ..< end])
        var after = end
        while after < input.count, input[after] == " " || input[after] == "\t" {
            after += 1
        }
        guard after < input.count, input[after] == ":" else {
            i = savedI
            return nil
        }

        i = after + 1
        skipWhitespace()
        return name
    }

    private mutating func parseKeywordEntity() -> String? {
        guard i < input.count, input[i].isLetter || input[i] == "-" else { return nil }

        var end = i
        if input[end] == "-" {
            end += 1
            guard end < input.count, input[end].isLetter else { return nil }
        }
        while end < input.count, input[end].isLetter || input[end] == "-" || input[end].isNumber
            || input[end] == "_"
        {
            end += 1
        }
        let value: String = .init(input[i ..< end])
        i = end
        skipWhitespace()
        return value
    }

    private mutating func parseDimensionEntity() -> Node? {
        guard i < input.count else { return nil }

        let c = input[i]
        // carto: skip unless -, ., or digit (carto's ascii range check)
        guard c == "-" || c == "." || isDigit(c) else { return nil }

        var end = i
        var seenDigit = false
        var seenDot = false
        if input[end] == "-" { end += 1 }
        while end < input.count {
            let ch = input[end]
            if isDigit(ch) {
                seenDigit = true
                end += 1
            }
            else if ch == ".", !seenDot {
                seenDot = true
                end += 1
            }
            else {
                break
            }
        }
        guard seenDigit else { return nil }

        var valueString: String = .init(input[i ..< end])
        // Exponent
        if end < input.count, input[end] == "e" || input[end] == "E" {
            var expEnd = end + 1
            if expEnd < input.count, input[expEnd] == "+" || input[expEnd] == "-" {
                expEnd += 1
            }
            var expDigits = 0
            while expEnd < input.count, isDigit(input[expEnd]) {
                expEnd += 1
                expDigits += 1
            }
            if expDigits > 0 {
                valueString = String(input[i ..< expEnd])
                end = expEnd
            }
        }
        // Unit
        var unit: String?
        if end < input.count {
            if input[end] == "%" {
                unit = "%"
                end += 1
            }
            else if input[end].isLetter {
                var unitEnd = end
                while unitEnd < input.count, isNameChar(input[unitEnd]) {
                    unitEnd += 1
                }
                unit = String(input[end ..< unitEnd])
                end = unitEnd
            }
        }
        i = end
        skipWhitespace()
        memo = i
        return .dimension(Dimension(value: Double(valueString) ?? 0, unit: unit))
    }

    private mutating func parseColorEntity() -> Node? {
        guard i < input.count, input[i] == "#" else { return nil }

        var end = i + 1
        var length = 0
        while end < input.count, isHexDigit(input[end]), length < 6 {
            end += 1
            length += 1
        }
        guard length == 3 || length == 6 else { return nil }

        let hex: String = .init(input[(i + 1) ..< end])
        i = end
        skipWhitespace()

        let rgb = Color.hexToRGB(hex)
        let hsl = Color.rgbToHSL(rgb)
        return .color(Color(h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2))
    }

    private func isHexDigit(_ c: Character) -> Bool {
        c.isHexDigit
    }

    private mutating func parseKeywordColorEntity() -> Node? {
        guard i < input.count, input[i].isLetter else { return nil }

        var end = i
        while end < input.count, input[end].isLetter {
            end += 1
        }
        let name: String = .init(input[i ..< end])
        guard let rgb = Reference.colors[name] else { return nil }

        i = end
        skipWhitespace()
        let alpha = rgb.count > 3 ? rgb[3] : 1
        let hsl = Color.rgbToHSL(rgb)
        return .color(Color(h: hsl.0.isNaN ? 0 : hsl.0, s: hsl.1, l: hsl.2, alpha: alpha))
    }

    private mutating func parseCallEntity() throws -> Node? {
        // name(
        let start = i
        guard i < input.count else { return nil }

        var end = i
        while end < input.count, isNameChar(input[end]) || input[end] == "%" {
            end += 1
        }
        guard end > i, end < input.count, input[end] == "(" else { return nil }

        let name: String = .init(input[i ..< end])
        if name == "url" { return nil }
        i = end + 1
        skipWhitespace()

        var args: [Node] = []
        if let first = try parseExpression() {
            args.append(first)
            while switchToken(",") != nil {
                if let next = try parseExpression() {
                    args.append(next)
                }
                else {
                    break
                }
            }
        }

        guard switchToken(")") != nil else {
            i = start
            return nil
        }

        return .call(Call(name: name, args: args, index: start, filename: env.filename))
    }

    private mutating func parseURLEntity() throws -> Node? {
        guard i + 3 < input.count,
              input[i] == "u", input[i + 1] == "r", input[i + 2] == "l",
              input[i + 3] == "("
        else { return nil }

        i += 4
        skipWhitespace()

        let value: Node
        if let quoted = parseQuotedEntity() {
            value = .quoted(quoted)
        }
        else if let variable = parseVariableEntity() {
            value = variable
        }
        else {
            // bare token
            var end = i
            while end < input.count,
                  input[end] != ")", input[end] != " ", input[end] != "\n", input[end] != ";"
            {
                end += 1
            }
            let raw: String = .init(input[i ..< end])
            i = end
            skipWhitespace()
            value = raw.isEmpty ? .keyword("") : .quoted(raw)
        }

        guard switchToken(")") != nil else {
            throw CartoError("Missing closing ) in URL. in \(env.filename ?? "input")")
        }

        return value
    }

    // MARK: - Rules

    private mutating func parseRule() throws -> MSSNode? {
        guard i < input.count else { return nil }

        let c = input[i]
        if c == "." || c == "#" { return nil }

        let savedI = i
        let savedMemo = memo

        var name: String?
        if let variableName = parseVariableDefinition() {
            name = variableName
        }
        else if let propertyName = parseProperty() {
            name = propertyName
        }

        guard let ruleName = name else {
            i = savedI
            memo = savedMemo
            return nil
        }

        // value
        var expressions: [Node] = []
        while let expression = try parseExpression() {
            expressions.append(expression)
            skipWhitespace()
            if switchToken(",") == nil { break }
            skipWhitespace()
        }

        guard !expressions.isEmpty else {
            i = savedI
            memo = savedMemo
            return nil
        }

        let value: Value
        if expressions.count > 1 {
            // carto flattens: Value(expressions.map(e => e.value[0]))
            value = Value(values: expressions)
        }
        else if let first = expressions.first {
            value = Value(values: [first])
        }
        else {
            i = savedI
            memo = savedMemo
            return nil
        }

        // end: ';' or peek '}'
        skipWhitespace()
        let ended = if switchToken(";") != nil {
            true
        }
        else if i < input.count, input[i] == "}" {
            true
        }
        else {
            false
        }

        guard ended else {
            i = savedI
            memo = savedMemo
            return nil
        }

        // carto's save() sets memo = i at rule start; the index is the
        // rule's start position.
        memo = savedI
        return .rule(Rule(name: ruleName, value: value, index: savedI, filename: env.filename))
    }

    /// A property name with optional `instance/` prefix.
    private mutating func parseProperty() -> String? {
        let savedI = i
        var end = i
        var nameEnd = end

        // optional instance prefix: [a-z][-a-z_0-9]*/
        if input[end].isLetter {
            var p = end
            while p < input.count, input[p].isLetter || input[p] == "-" || input[p] == "_"
                || input[p].isNumber
            {
                p += 1
            }
            if p < input.count, input[p] == "/", p + 1 < input.count,
               input[p + 1].isLetter || input[p + 1] == "-" || input[p + 1] == "*"
            {
                p += 1
                end = p
            }
        }
        else if input[end] == "*" {
            // handled below
        }

        // main name: *?-?[-a-z_0-9]+
        if end < input.count, input[end] == "*" {
            end += 1
        }
        if end < input.count, input[end] == "-" {
            end += 1
        }
        guard end < input.count, input[end].isLetter || input[end] == "-" else {
            i = savedI
            return nil
        }

        while end < input.count, input[end].isLetter || input[end] == "-" || input[end] == "_"
            || input[end].isNumber
        {
            end += 1
        }
        nameEnd = end

        var after = end
        while after < input.count, input[after] == " " || input[after] == "\t" {
            after += 1
        }
        guard after < input.count, input[after] == ":" else {
            i = savedI
            return nil
        }

        i = after + 1
        skipWhitespace()
        let name: String = .init(input[savedI ..< nameEnd])
        memo = savedI
        return name
    }

    // MARK: - Expressions

    private mutating func parseExpression() throws -> Node? {
        var entities: [Node] = []

        while true {
            let e = try parseAddition()
            if let e {
                entities.append(e)
            }
            else if let entity = try parseEntity() {
                entities.append(entity)
            }
            else {
                break
            }
            skipWhitespace()
            // no comma directly consumed here (values are comma-separated at
            // the Value level)
            guard i < input.count else { break }

            let c = input[i]
            if c == ";" || c == "}" || c == "," || c == "]" || c == ")" { break }
        }

        guard !entities.isEmpty else { return nil }

        return .expression(entities)
    }

    private mutating func parseAddition() throws -> Node? {
        var lhs = try parseMultiplication()
        guard lhs != nil else { return nil }

        while true {
            let savedI = i
            skipWhitespace()
            var op: Operation.Op?
            // carto: /^[-+]\s+/ (sign followed by space) OR no-space +/-.
            if i < input.count {
                let c = input[i]
                let prevWasSpace = i > 0 && (input[i - 1] == " " || input[i - 1] == "\n" || input[i - 1] == "\t")
                if c == "+" || c == "-" {
                    let isOp = (c == "+" && prevWasSpace) || !prevWasSpace || (i + 1 < input.count && input[i + 1] == " ")
                    if isOp {
                        op = c == "+" ? .add : .subtract
                        i += 1
                        skipWhitespace()
                    }
                }
            }

            if let op {
                skipWhitespace()
                if let rhs = try parseMultiplication() {
                    lhs = .operation(Operation(op: op, lhs: lhs!, rhs: rhs))
                    continue
                }
                else {
                    i = savedI
                    break
                }
            }
            i = savedI
            break
        }

        return lhs
    }

    private mutating func parseMultiplication() throws -> Node? {
        var lhs = try parseOperand()
        guard lhs != nil else { return nil }

        while true {
            let savedI = i
            skipWhitespace()
            var op: Operation.Op?
            if i < input.count {
                switch input[i] {
                case "*": op = .multiply
                case "/": op = .divide
                case "%": op = .modulo
                default: break
                }
            }
            if let op {
                i += 1
                skipWhitespace()
                if let rhs = try parseOperand() {
                    lhs = .operation(Operation(op: op, lhs: lhs!, rhs: rhs))
                    continue
                }
                else {
                    i = savedI
                    break
                }
            }
            i = savedI
            break
        }

        return lhs
    }

    private mutating func parseOperand() throws -> Node? {
        // sub-expression `( ... )`
        if i < input.count, input[i] == "(" {
            let savedI = i
            i += 1
            skipWhitespace()
            if let expression = try parseExpression() {
                skipWhitespace()
                if switchToken(")") != nil {
                    return expression
                }
            }
            i = savedI
        }
        return try parseEntity()
    }

    private mutating func parseEntity() throws -> Node? {
        if let call = try parseCallEntity() { return call }
        if let literal = parseLiteralEntity() { return literal }
        if let field = parseFieldEntity() { return field }
        if let variable = parseVariableEntity() { return variable }
        if let url = try parseURLEntity() { return url }
        if let keyword = parseKeywordEntity() { return .keyword(keyword) }
        return nil
    }

    private mutating func parseLiteral() -> Node? {
        if let dimension = parseDimensionEntity() { return dimension }
        if let color = parseKeywordColorEntity() { return color }
        if let hex = parseColorEntity() { return hex }
        if let quoted = parseQuotedEntity() { return .quoted(quoted) }
        return nil
    }

}

extension MSSParser {

    private mutating func parseLiteralEntity() -> Node? {
        parseLiteral()
    }

}

/// A zoom condition node (`[zoom>=3]`), pre-evaluation.
struct ZoomNode {

    var op: Filter.Op
    var value: Node
    var index: Int

}
