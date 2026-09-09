//
//  Created by Thomas Rasch, 2026.
//

import Foundation

/// A single `[key op value]` filter condition.
struct Filter {

    enum Op: String {
        case eq = "="
        case neq = "!="
        case lt = "<"
        case gt = ">"
        case lte = "<="
        case gte = ">="
        case match = "=~"
    }

    var key: Node
    var op: Op
    var value: Node
    var index: Int
    var filename: String?

    /// Canonical identity used for deduplication and ordering, mirroring
    /// carto's `filter.id` (`key + op + value`).
    var id: String {
        Filter.idString(key: key, op: op, value: value)
    }

    static func idString(key: Node, op: Op, value: Node) -> String {
        key.idString + op.rawValue + value.idString
    }

    /// The Mapnik filter expression fragment, e.g. `[key] = 'value'`.
    func toObject(_ messages: inout Messages) -> String {
        let opString = switch op {
        case .eq: " = "
        case .neq: " != "
        case .lt: " < "
        case .gt: " > "
        case .lte: " <= "
        case .gte: " >= "
        case .match: ".match("
        }

        let keyString = key.isFieldLike ? key.idString : "[\(key.idString)]"
        let isString = value.isString
        let valueString = value.filterString(quoted: isString)

        // carto validates keyword literals in filters against the
        // reference's filter keyword list.
        if case let .keyword(keyword) = key, !Reference.filterKeywords.contains(keyword) {
            messages.error(
                "\(keyword) is not a valid keyword in a filter expression",
                filename: filename, index: index)
        }
        if case let .keyword(keyword) = value,
           !Reference.filterKeywords.contains(keyword)
        {
            messages.error(
                "\(keyword) is not a valid keyword in a filter expression",
                filename: filename, index: index)
        }

        if op == .match {
            if !valueString.hasPrefix("'") {
                messages.error(
                    "Cannot use operator \"\(op.rawValue)\" with value \(valueString)",
                    filename: filename, index: index)
            }
            return keyString + opString + valueString + ")"
        }

        let numericOp = op != .eq && op != .neq
        if numericOp, Double(valueString) == nil, !value.isField {
            messages.error(
                "Cannot use operator \"\(op.rawValue)\" with value \(valueString)",
                filename: filename, index: index)
        }

        return keyString + opString + valueString
    }

}

extension Node {

    /// The string form used in filter ids and filter expressions (unquoted,
    /// raw), mirroring carto's `toString()`.
    var idString: String {
        switch self {
        case let .dimension(d): formatNumber(d.value)
        case let .color(c): c.serialized()
        case let .quoted(s): s
        case let .keyword(s): s
        case let .field(s): "[\(s)]"
        case let .literal(s): s
        case let .url(s): s
        case let .variable(name, _, _): name
        case let .operation(op):
            op.lhs.idString + " " + op.op.rawValue + " " + op.rhs.idString
        case let .expression(nodes): nodes.map(\.idString).joined(separator: " ")
        case let .call(call):
            call.name + "(" + call.args.map(\.idString).joined(separator: ",") + ")"
        case let .value(v):
            v.values.map(\.idString).joined(separator: ", ")
        case .tag: "tag"
        case let .imageFilter(name, _): name
        case .undefined: "undefined"
        }
    }

    var isString: Bool {
        if case .quoted = self { return true }
        return false
    }

    var isField: Bool {
        switch self {
        case .field, .literal:
            true
        default:
            false
        }
    }

    var isKeywordNull: Bool {
        if case let .keyword(value) = self, value == "null" { return true }
        return false
    }

    /// Value serialization for filter expressions: strings get single-quoted
    /// with escaping, matching carto's `Filter.toObject`.
    func filterString(quoted: Bool) -> String {
        if quoted {
            let escaped = idString
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "'" + escaped + "'"
        }
        return idString
    }

}

/// A set of filters on a selector, keyed by `key + op` with carto's exact
/// simplification and conflict rules (`tree.Filterset`).
///
/// carto stores filters in an object keyed `key + op` (one filter per
/// key+op pair; adding an `=` deletes all other filters on the key, adding
/// `>=` replaces a narrower `!=` with `>`, etc). We mirror that with a
/// dictionary plus a stable insertion-ordered key list.
struct FilterSet {

    private(set) var filters: [String: Filter] = [:]
    /// Insertion order of the key ids, for stable output.
    private(set) var order: [String] = []

    /// Append a key only if not already present (the dict slot may be
    /// overwritten by later adds).
    private mutating func touchOrder(_ key: String) {
        if !order.contains(key) {
            order.append(key)
        }
    }

    var isEmpty: Bool {
        filters.isEmpty
    }

    var count: Int {
        filters.count
    }

    /// All filters in insertion order.
    var allFilters: [Filter] {
        order.compactMap { filters[$0] }
    }

    /// Add a filter. Returns an error message on conflict, `nil` on success.
    /// Mirrors `tree.Filterset.conflict` + `add` (which assumes addable()).
    mutating func add(_ filter: Filter) -> String? {
        let key = filter.key.idString
        let value = filter.value.idString
        let op = filter.op

        if let conflict = checkConflict(filter) {
            return conflict
        }

        switch op {
        case .eq:
            // `=` replaces everything for that key.
            for (id, existing) in filters where existing.key.idString == key {
                filters[id] = nil
                order.removeAll { $0 == id }
            }
            filters[key + "="] = filter
            touchOrder(key + "=")

        case .neq:
            filters[key + "!=" + value] = filter
            touchOrder(key + "!=" + value)

        case .match:
            filters[key + "=~" + value] = filter
            touchOrder(key + "=~" + value)

        case .gt:
            filters[key + ">"] = filter
            touchOrder(key + ">")

        case .gte:
            for (id, existing) in filters {
                if existing.key.idString == key, let numval = Double(existing.value.idString),
                   let newval = Double(value), numval < newval
                {
                    filters[id] = nil
                    order.removeAll { $0 == id }
                }
            }
            let neqId = key + "!=" + value
            if filters[neqId] != nil {
                filters[neqId] = nil
                order.removeAll { $0 == neqId }
                var upgraded = filter
                upgraded.op = .gt
                filters[key + ">"] = upgraded
                touchOrder(key + ">")
            }
            else {
                filters[key + ">="] = filter
                touchOrder(key + ">=")
            }

        case .lt:
            for (id, existing) in filters {
                if existing.key.idString == key, let numval = Double(existing.value.idString),
                   let newval = Double(value), numval >= newval
                {
                    filters[id] = nil
                    order.removeAll { $0 == id }
                }
            }
            filters[key + "<"] = filter
            touchOrder(key + "<")

        case .lte:
            for (id, existing) in filters {
                if existing.key.idString == key, let numval = Double(existing.value.idString),
                   let newval = Double(value), numval > newval
                {
                    filters[id] = nil
                    order.removeAll { $0 == id }
                }
            }
            let neqId = key + "!=" + value
            if filters[neqId] != nil {
                filters[neqId] = nil
                order.removeAll { $0 == neqId }
                var upgraded = filter
                upgraded.op = .lt
                filters[key + "<"] = upgraded
                touchOrder(key + "<")
            }
            else {
                filters[key + "<="] = filter
                touchOrder(key + "<=")
            }
        }

        // The order array can accumulate duplicates from deletions; rebuild.
        order = order.filter { filters[$0] != nil }
        return nil
    }

    /// carto's `Filterset.conflict`.
    private func checkConflict(_ filter: Filter) -> String? {
        let key = filter.key.idString
        let value = filter.value.idString

        switch filter.op {
        case .eq:
            if let existing = filters[key + "="],
               value != existing.value.idString
            {
                return "[\(filter.id)] added to \(idString) produces an invalid filter"
            }
            if let existing = filters[key + "!=" + value],
               value == existing.value.idString
            {
                return "[\(filter.id)] added to \(idString) produces an invalid filter"
            }

        case .neq:
            if let existing = filters[key + "="],
               value == existing.value.idString
            {
                return "[\(filter.id)] added to \(idString) produces an invalid filter"
            }

        default:
            break
        }
        return nil
    }

    /// carto's `cloneWith` tri-state.
    enum MergeResult {
        case conflict
        case merged(FilterSet)
        case unchanged
    }

    /// Merge `other` into this set (as a clone). Mirrors `cloneWith`.
    func merging(_ other: FilterSet) -> MergeResult {
        var additions: [Filter] = []
        for filter in other.allFilters {
            switch addable(filter) {
            case .conflict:
                return .conflict
            case .redundant:
                continue
            case .addable:
                additions.append(filter)
            }
        }

        if additions.isEmpty {
            return .unchanged
        }

        var merged = self
        for filter in additions {
            _ = merged.add(filter)
        }
        return .merged(merged)
    }

    enum AddableResult {
        case addable
        case conflict
        case redundant
    }

    /// carto's `addable` tri-state (true/false/null → addable/conflict/redundant).
    ///
    /// Faithful to carto's JS: the new value is `parseFloat`d when it looks
    /// numeric; comparisons then follow JS coercion (existing side is
    /// `toString`d — numeric compare when the new side is a number and the
    /// existing side parses, string compare otherwise, NaN → false).
    func addable(_ filter: Filter) -> AddableResult {
        let key = filter.key.idString
        let valueString = filter.value.idString
        let valueIsNull = filter.value.isKeywordNull
        // carto: value.match(/^[+-]?[0-9]+(\.[0-9]*)?([e|E][+-]?[0-9]+)?$/) → parseFloat
        let numericValue = Self.numericPattern.matches(valueString)
            ? Double(valueString)
            : nil

        func existing(_ op: Filter.Op) -> Filter? {
            filters[key + op.keySuffix(value: valueString)]
        }
        /// JS `existing.val OP value` with the coercion rules above.
        func compares(_ op: Filter.Op, numeric: (Double, Double) -> Bool, string: (String, String) -> Bool) -> Bool {
            guard let e = existing(op) else { return false }

            let existingString = e.value.idString
            if let newValue = numericValue {
                // value is a number: the existing string is coerced (NaN → false)
                if let e = Double(existingString) {
                    return numeric(e, newValue)
                }
                return false
            }
            // value is a string: both sides compare as strings
            return string(existingString, valueString)
        }
        /// JS `existing.val != value` / `== value` with coercion.
        func equals(_ op: Filter.Op) -> Bool {
            guard let e = existing(op) else { return false }

            let existingString = e.value.idString
            if let newValue = numericValue, let e2 = Double(existingString) {
                return e2 == newValue
            }
            return existingString == valueString
        }
        func existingIsNull(_ op: Filter.Op) -> Bool {
            existing(op)?.value.isKeywordNull ?? false
        }

        switch filter.op {
        case .eq:
            if existing(.eq) != nil {
                return equals(.eq) ? .redundant : .conflict
            }
            if existing(.neq) != nil { return .conflict }
            if compares(.gt, numeric: { $0 >= $1 }, string: { $0 >= $1 }) || valueIsNull { return .conflict }
            if compares(.lt, numeric: { $0 <= $1 }, string: { $0 <= $1 }) || valueIsNull { return .conflict }
            if compares(.gte, numeric: { $0 > $1 }, string: { $0 > $1 }) || valueIsNull { return .conflict }
            if compares(.lte, numeric: { $0 < $1 }, string: { $0 < $1 }) || valueIsNull { return .conflict }
            return .addable

        case .match:
            return .addable

        case .neq:
            if existing(.eq) != nil {
                return equals(.eq) ? .conflict : .redundant
            }
            if let e = existing(.neq), e.value.idString == valueString { return .redundant }
            if compares(.gt, numeric: { $0 >= $1 }, string: { $0 >= $1 }) || valueIsNull { return .redundant }
            if compares(.lt, numeric: { $0 <= $1 }, string: { $0 <= $1 }) || valueIsNull { return .redundant }
            if compares(.gte, numeric: { $0 > $1 }, string: { $0 > $1 }) || valueIsNull { return .redundant }
            if compares(.lte, numeric: { $0 < $1 }, string: { $0 < $1 }) || valueIsNull { return .redundant }
            return .addable

        case .gt:
            if existing(.eq) != nil {
                if compares(.eq, numeric: { $0 <= $1 }, string: { $0 <= $1 }) || existingIsNull(.eq) {
                    return .conflict
                }
                return .redundant
            }
            if compares(.lt, numeric: { $0 <= $1 }, string: { $0 <= $1 }) { return .conflict }
            if compares(.lte, numeric: { $0 <= $1 }, string: { $0 <= $1 }) { return .conflict }
            if compares(.gt, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .redundant }
            if compares(.gte, numeric: { $0 > $1 }, string: { $0 > $1 }) { return .redundant }
            return .addable

        case .gte:
            if existing(.eq) != nil {
                if compares(.eq, numeric: { $0 < $1 }, string: { $0 < $1 }) || existingIsNull(.eq) {
                    return .conflict
                }
                return .redundant
            }
            if compares(.lt, numeric: { $0 <= $1 }, string: { $0 <= $1 }) { return .conflict }
            if compares(.lte, numeric: { $0 < $1 }, string: { $0 < $1 }) { return .conflict }
            if compares(.gt, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .redundant }
            if compares(.gte, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .redundant }
            return .addable

        case .lt:
            if existing(.eq) != nil {
                if compares(.eq, numeric: { $0 >= $1 }, string: { $0 >= $1 }) || existingIsNull(.eq) {
                    return .conflict
                }
                return .redundant
            }
            if compares(.gt, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .conflict }
            if compares(.gte, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .conflict }
            if compares(.lt, numeric: { $0 <= $1 }, string: { $0 <= $1 }) { return .redundant }
            if compares(.lte, numeric: { $0 < $1 }, string: { $0 < $1 }) { return .redundant }
            return .addable

        case .lte:
            if existing(.eq) != nil {
                if compares(.eq, numeric: { $0 > $1 }, string: { $0 > $1 }) || existingIsNull(.eq) {
                    return .conflict
                }
                return .redundant
            }
            if compares(.gt, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .conflict }
            if compares(.gte, numeric: { $0 >= $1 }, string: { $0 >= $1 }) { return .conflict }
            if compares(.lt, numeric: { $0 <= $1 }, string: { $0 <= $1 }) { return .redundant }
            if compares(.lte, numeric: { $0 <= $1 }, string: { $0 <= $1 }) { return .redundant }
            return .addable
        }
    }

    /// carto's numeric-value regex: `/^[+-]?[0-9]+(\.[0-9]*)?([e|E][+-]?[0-9]+)?$/`.
    private static let numericPattern: NumericPattern = .init()

    /// The sorted tab-separated id list used to identify filtersets
    /// (carto's `toString`).
    var idString: String {
        filters.values.map(\.id).sorted().joined(separator: "\t")
    }

    /// Mapnik `<Filter>` content: `([a] = 'x') and ([b] > 2)`.
    func toObject(_ messages: inout Messages) -> String {
        order
            .compactMap { filters[$0] }
            .map { "(" + $0.toObject(&messages).trimmingCharacters(in: .whitespaces) + ")" }
            .joined(separator: " and ")
    }

}

extension Filter.Op {

    /// The suffix carto uses in its filter dictionary keys. `!=` and `=~`
    /// keys include the value (carto's `add`).
    func keySuffix(value: String) -> String {
        switch self {
        case .eq: "="
        case .neq: "!=" + value
        case .lt: "<"
        case .gt: ">"
        case .lte: "<="
        case .gte: ">="
        case .match: "=~" + value
        }
    }

}

extension Filter {

    /// The numeric value of the filter value, if it parses as a number
    /// (carto compares `val` with `parseFloat` semantics).
    func numericValue() -> Double? {
        Double(value.idString)
    }

}

extension Node {

    func numericValue() -> Double? {
        Double(idString)
    }

}

/// Minimal matcher for carto's numeric value pattern
/// `^[+-]?[0-9]+(\.[0-9]*)?([e|E][+-]?[0-9]+)?$`.
struct NumericPattern {

    func matches(_ value: String) -> Bool {
        var characters: Substring = .init(value)
        if characters.hasPrefix("+") || characters.hasPrefix("-") {
            characters = characters.dropFirst()
        }
        var digits = 0
        while let first = characters.first, first.isNumber {
            characters = characters.dropFirst()
            digits += 1
        }
        guard digits > 0 else { return false }

        if characters.hasPrefix(".") {
            characters = characters.dropFirst()
            while let first = characters.first, first.isNumber {
                characters = characters.dropFirst()
            }
        }
        if let first = characters.first, first == "e" || first == "E" {
            characters = characters.dropFirst()
            if let first = characters.first, first == "+" || first == "-" {
                characters = characters.dropFirst()
            }
            var exponentDigits = 0
            while let first = characters.first, first.isNumber {
                characters = characters.dropFirst()
                exponentDigits += 1
            }
            guard exponentDigits > 0 else { return false }
        }
        return characters.isEmpty
    }

}
