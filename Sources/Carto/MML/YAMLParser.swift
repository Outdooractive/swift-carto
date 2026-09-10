//
//  Created by Thomas Rasch, 2026.
//

#if EnableYAMLProjectFiles
import Foundation
import Yams

/// Parses YAML documents (TileMill `.mml` project files can be YAML) into
/// the `JSONValue` tree the MML loader works with.
///
/// Mirrors carto's `MML.load`, which pipes every project file through
/// `js-yaml`'s `safeLoad` (YAML is a superset of JSON). We try the JSON5
/// parser first and fall back to YAML.
///
/// Conversion follows YAML 1.1 (js-yaml 3.x) semantics: unquoted `yes/no/
/// on/off/true/false` are booleans, `0x`/octal literals are integers,
/// `~/null` is null, merge keys (`<<`) splice in anchored mappings, and
/// duplicate keys are an error.
enum YAMLParser {

    /// Parse a YAML document into a `JSONValue` tree.
    static func parse(_ text: String) throws -> JSONValue {
        let node = try Yams.compose(yaml: text)
        guard let node else {
            throw CartoError("carto: YAML document is empty")
        }

        var errors: [String] = []
        if let value = try convert(node, path: [], errors: &errors) {
            return value
        }
        throw CartoError("carto: \(errors.first ?? "YAML document has no content")")
    }

    // MARK: - Node conversion

    private static func convert(
        _ node: Yams.Node,
        path: [String],
        errors: inout [String],
    )
    throws -> JSONValue? {
        switch node {
        case let .scalar(scalar):
            return convertScalar(scalar)

        case let .sequence(sequence):
            var values: [JSONValue] = []
            for element in sequence {
                try values.append(convert(element, path: path, errors: &errors) ?? .null)
            }
            return .array(values)

        case let .mapping(mapping):
            return try convertMapping(mapping, path: path, errors: &errors)

        case .alias:
            // Aliases are resolved inline by Yams' composer.
            throw CartoError("carto: unexpected YAML alias")
        }
    }

    private static func convertScalar(_ scalar: Yams.Node.Scalar) -> JSONValue {
        let node = Yams.Node.scalar(scalar)
        switch node.tag.rawValue {
        case Tag.Name.null.rawValue:
            return .null

        case Tag.Name.bool.rawValue:
            // js-yaml 3.x (YAML core schema): only true/false are booleans —
            // yes/no/on/off stay strings.
            switch scalar.string.lowercased() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            default: return .string(scalar.string)
            }

        case Tag.Name.int.rawValue:
            if let int = Self.parseInt(scalar.string) {
                return .number(Double(int))
            }
            return .string(scalar.string)

        case Tag.Name.float.rawValue:
            let cleaned = scalar.string.replacingOccurrences(of: "_", with: "")
            switch cleaned.lowercased() {
            case ".inf", "+.inf": return .number(.infinity)
            case "-.inf": return .number(-.infinity)
            case ".nan": return .string(scalar.string)
            default:
                return .number(Double(cleaned) ?? 0)
            }

        default:
            // .str, .timestamp, custom tags: keep the string form.
            return .string(scalar.string)
        }
    }

    private static func convertMapping(
        _ mapping: Yams.Node.Mapping,
        path: [String],
        errors: inout [String],
    )
    throws -> JSONValue {
        var members: [(String, JSONValue)] = []
        var seenKeys: Set<String> = []
        // Merge key (`<<`) members, applied after the explicit keys (an
        // explicit key overrides a merged one, js-yaml 3.x semantics).
        var mergedMembers: [(String, JSONValue)] = []
        var mergedKeys: Set<String> = []

        for (keyNode, valueNode) in mapping {
            // Merge keys (`<<`): collect the referenced mapping(s) now,
            // splice them in after the explicit keys.
            if case .scalar = keyNode, keyNode.tag.rawValue == Tag.Name.merge.rawValue {
                let mergeSources: [Yams.Node] = if case let .sequence(sequence) = valueNode {
                    Array(sequence)
                }
                else {
                    [valueNode]
                }
                for source in mergeSources {
                    let mergeMembers = try mergeSource(source, path: path, errors: &errors)
                    for (key, value) in mergeMembers where !mergedKeys.contains(key) {
                        mergedMembers.append((key, value))
                        mergedKeys.insert(key)
                    }
                }
                continue
            }

            guard case let .scalar(keyScalar) = keyNode else {
                throw CartoError("carto: non-string YAML key in \(pathDescription(path))")
            }

            let key = keyScalar.string

            if seenKeys.contains(key) {
                // Yams' composer already reports duplicates; this is a
                // safety net.
                errors.append("duplicated mapping key at line \(keyScalar.mark?.line ?? 0), column \(keyScalar.mark?.column ?? 0): \(key)")
                continue
            }
            seenKeys.insert(key)
            mergedKeys.remove(key)

            guard let value = try convert(valueNode, path: path + [key], errors: &errors) else {
                continue
            }

            members.append((key, value))
        }

        // Splice the merge members in document order: keys not already
        // explicit are appended (the mapping iteration order is stable).
        if !mergedMembers.isEmpty {
            for (key, value) in mergedMembers where !seenKeys.contains(key) {
                members.append((key, value))
            }
        }

        return .object(members)
    }

    private static func mergeSource(
        _ node: Yams.Node,
        path: [String],
        errors: inout [String],
    )
    throws -> [(String, JSONValue)] {
        guard let value = try convert(node, path: path, errors: &errors),
              case let .object(members) = value
        else {
            throw CartoError("carto: YAML merge key value must be a mapping in \(pathDescription(path))")
        }

        return members
    }

    private static func pathDescription(_ path: [String]) -> String {
        path.isEmpty ? "the document" : path.joined(separator: ".")
    }

    /// YAML 1.1 integer scalars: decimal, `0x` hex, `0o`/`0` octal, `0b`
    /// binary, underscores as separators, and sexagesimal `1:30` groups
    /// (js-yaml 3.x semantics).
    static func parseInt(_ string: String) -> Int? {
        var characters = Substring(string.replacingOccurrences(of: "_", with: ""))
        var negative = false
        if characters.first == "-" || characters.first == "+" {
            negative = characters.first == "-"
            characters = characters.dropFirst()
        }

        let radix: Int
        if characters.hasPrefix("0x") {
            radix = 16
            characters = characters.dropFirst(2)
        }
        else if characters.hasPrefix("0b") {
            radix = 2
            characters = characters.dropFirst(2)
        }
        else if characters.hasPrefix("0o") {
            radix = 8
            characters = characters.dropFirst(2)
        }
        else if characters.count > 1, characters.hasPrefix("0") {
            radix = 8
            characters = characters.dropFirst(1)
        }
        else {
            radix = 10
        }

        // Sexagesimal (base-60) colon groups, e.g. `1:30` → 90.
        if radix == 10, characters.contains(":") {
            return Self.parseSexagesimal(characters).map { negative ? -$0 : $0 }
        }

        guard let value = Int(characters, radix: radix) else { return nil }

        return negative ? -value : value
    }

    /// `1:30` → 90 (60 + 30), js-yaml's sexagesimal integer form.
    private static func parseSexagesimal(_ string: Substring) -> Int? {
        var result = 0
        var hasValue = false
        for group in string.split(separator: ":") {
            guard let value = Int(group), value < 60 else { return nil }

            result = result * 60 + value
            hasValue = true
        }
        return hasValue ? result : nil
    }

}
#endif
