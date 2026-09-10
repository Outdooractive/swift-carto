//
//  Created by Thomas Rasch, 2026.
//

@testable import Carto
import Foundation
import Testing

/// Runs the bundled rendering fixtures (from carto's test corpus) and compares
/// the produced XML against the expected `.result` files as XML trees,
/// mirroring carto's own test harness: element order, attribute values, and
/// text content must match; formatting/CDATA/entity differences do not.
struct RenderingTests {

    @Test(arguments: {
        var fixtures = [
            "complex_cascades", "field", "filters", "instance_names",
            "partial_overrides", "simplevariabletest", "units", "zoomselector",
            "zoom_variables",
        ]
        #if EnableYAMLProjectFiles
        fixtures.append("zoomselector_yaml")
        #endif
        return fixtures
    }())
    func rendering(fixture: String) throws {
        let fixtureURL = Bundle.module
            .bundleURL
            .appendingPathComponent("Fixtures", isDirectory: true)
        let mmlData = try String(
            contentsOf: fixtureURL.appendingPathComponent(fixture + ".mml"), encoding: .utf8)
        let expectedResult = try String(
            contentsOf: fixtureURL.appendingPathComponent(fixture + ".result"), encoding: .utf8)

        let mml = try MML(data: mmlData, basedir: fixtureURL)
        var renderer = Renderer()
        guard let xml = renderer.render(mml) else {
            struct RenderFailure: Error, CustomStringConvertible {
                let description: String
            }
            Issue.record(
                RenderFailure(
                    description: "Rendering \(fixture) failed: "
                        + renderer.messages.map(\.description).joined(separator: "; ")))
            return
        }

        let expected = Self.parseXML(expectedResult)
        let actual = Self.parseXML(xml)
        #expect(Self.treesEqual(expected, actual), "XML tree mismatch for \(fixture)")
    }

    // MARK: - XML tree parsing

    struct ValueNode {
        var name: String
        var attributes: [String: String]
        var text: String?
        var children: [ValueNode]
    }

    /// Minimal XML scanner: builds an ordered element tree. CDATA content is
    /// unwrapped; entities are decoded in text and attribute values.
    private static func parseXML(_ xml: String) -> ValueNode {
        let chars = Array(xml)
        var position = 0
        let rootStart = ValueNode(name: "#root", attributes: [:], text: nil, children: [])
        var stack: [ValueNode] = [rootStart]

        func appendText(_ raw: String) {
            let text = decodeEntities(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let current = stack[stack.count - 1].text ?? ""
            stack[stack.count - 1].text = current + text
        }

        func hasMarker(_ marker: [Character]) -> Bool {
            guard position + marker.count <= chars.count else { return false }

            for (offset, c) in marker.enumerated() where chars[position + offset] != c {
                return false
            }
            return true
        }

        while position < chars.count {
            guard chars[position] == "<" else {
                var end = position
                while end < chars.count, chars[end] != "<" {
                    end += 1
                }
                appendText(String(chars[position ..< end]))
                position = end
                continue
            }

            if hasMarker(Array("<![CDATA[".map(\.self))) {
                position += 9
                var content = ""
                while position < chars.count {
                    if position + 2 < chars.count,
                       chars[position] == "]", chars[position + 1] == "]", chars[position + 2] == ">"
                    {
                        position += 3
                        break
                    }
                    content.append(chars[position])
                    position += 1
                }
                appendText(content)
                continue
            }
            if hasMarker(Array("<!--".map(\.self))) {
                while position + 2 < chars.count,
                      !(chars[position] == "-" && chars[position + 1] == "-" && chars[position + 2] == ">")
                {
                    position += 1
                }
                position += 3
                continue
            }
            if position + 1 < chars.count, chars[position + 1] == "?"
                || chars[position + 1] == "!"
            {
                while position < chars.count, chars[position] != ">" {
                    position += 1
                }
                position += 1
                continue
            }
            if position + 1 < chars.count, chars[position + 1] == "/" {
                while position < chars.count, chars[position] != ">" {
                    position += 1
                }
                position += 1
                guard stack.count > 1 else { continue }

                let finished = stack.removeLast()
                stack[stack.count - 1].children.append(finished)
                continue
            }

            // opening tag: scan to '>' honoring quotes
            var end = position
            var inQuote: Character?
            while end < chars.count {
                let c = chars[end]
                if let quote = inQuote {
                    if c == quote {
                        inQuote = nil
                    }
                }
                else if c == "\"" || c == "'" {
                    inQuote = c
                }
                else if c == ">" {
                    break
                }
                end += 1
            }
            guard end < chars.count else { break }

            var tagText = String(chars[(position + 1) ..< end])
            position = end + 1

            let selfClosing = tagText.hasSuffix("/")
            if selfClosing {
                tagText = String(tagText.dropLast())
            }

            let (name, attributes) = parseTag(
                tagText.trimmingCharacters(in: .whitespacesAndNewlines))
            let node = ValueNode(name: name, attributes: attributes, text: nil, children: [])

            if selfClosing {
                stack[stack.count - 1].children.append(node)
            }
            else {
                stack.append(node)
            }
        }

        while stack.count > 1 {
            let finished = stack.removeLast()
            stack[stack.count - 1].children.append(finished)
        }
        return stack[0]
    }

    private static func parseTag(_ tag: String) -> (String, [String: String]) {
        let parts = tag.split(
            maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        let name = String(parts[0])
        var attributes: [String: String] = [:]
        if parts.count > 1 {
            parseAttributes(String(parts[1]), into: &attributes)
        }
        return (name, attributes)
    }

    private static func parseAttributes(_ text: String, into attributes: inout [String: String]) {
        let chars = Array(text)
        var position = 0
        while position < chars.count {
            var key = ""
            while position < chars.count, chars[position] != "=", chars[position] != " " {
                key.append(chars[position])
                position += 1
            }
            guard position < chars.count, chars[position] == "=" else {
                position += 1
                continue
            }

            position += 1
            guard position < chars.count, chars[position] == "\"" else { continue }

            position += 1
            var value = ""
            while position < chars.count, chars[position] != "\"" {
                value.append(chars[position])
                position += 1
            }
            position += 1
            if !key.isEmpty {
                attributes[key] = decodeEntities(value)
            }
        }
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        return text
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Comparison

    private static func treesEqual(_ a: ValueNode, _ b: ValueNode) -> Bool {
        guard a.name == b.name, a.attributes == b.attributes else { return false }
        guard normalizePath(a.text) == normalizePath(b.text) else { return false }
        guard a.children.count == b.children.count else { return false }

        for (aChild, bChild) in zip(a.children, b.children) {
            if !treesEqual(aChild, bChild) {
                return false
            }
        }
        return true
    }

    private static func normalizePath(_ text: String?) -> String? {
        guard let text else { return nil }

        // carto's harness normalizes absolute file paths and URLs.
        if text.hasPrefix("/") || text.hasPrefix("http://") || text.hasPrefix("https://") {
            return "[absolute path]"
        }
        return text
    }

}
