//
//  Created by Thomas Rasch, 2026.
//

@testable import Carto
import Foundation
import Testing

/// Unit tests for the compiler internals — ported from carto's own test
/// suites (filterset.test.js, color.test.js, zoom, specificity).
struct UnitTests {

    // MARK: - Filterset (carto's filterset.test.js)

    private func makeFilter(_ key: String, _ op: Filter.Op, _ value: String) -> Filter {
        Filter(key: .field(key), op: op, value: .keyword(value), index: 0, filename: nil)
    }

    @Test func `filter set add basics`() {
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .eq, "11")) == nil)
        #expect(set.filters.count == 1)
        #expect(set.idString == "[TOTAL]=11")
    }

    @Test func `filter set conflicts`() {
        // =11 then =90 → conflict
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .eq, "11")) == nil)
        #expect(set.add(makeFilter("TOTAL", .eq, "90")) != nil)

        // =11 then !=11 → conflict
        set = FilterSet()
        #expect(set.add(makeFilter("TOTAL", .eq, "11")) == nil)
        #expect(set.add(makeFilter("TOTAL", .neq, "11")) != nil)

        // !=11 then =11 → conflict
        set = FilterSet()
        #expect(set.add(makeFilter("TOTAL", .neq, "11")) == nil)
        #expect(set.add(makeFilter("TOTAL", .eq, "11")) != nil)
    }

    @Test func `filter set redundant`() {
        // =11 then =11 again → deduplicated
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .eq, "11")) == nil)
        #expect(set.add(makeFilter("TOTAL", .eq, "11")) == nil)
        #expect(set.filters.count == 1)
    }

    @Test func `filter set merge redundant`() {
        // >11 then >9 → >9 redundant (addable keeps both in carto's add,
        // but addable reports null = redundant)
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .gt, "11")) == nil)
        #expect(set.addable(makeFilter("TOTAL", .gt, "9")) == .redundant)
        #expect(set.addable(makeFilter("TOTAL", .gte, "9")) == .redundant)
        #expect(set.addable(makeFilter("TOTAL", .gt, "90")) == .addable)
    }

    @Test func `filter set merge conflict`() {
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .gt, "11")) == nil)
        // >11 then <9 → conflict
        #expect(set.addable(makeFilter("TOTAL", .lt, "9")) == .conflict)
        #expect(set.addable(makeFilter("TOTAL", .lte, "9")) == .conflict)
        #expect(set.addable(makeFilter("TOTAL", .lt, "90")) == .addable)
    }

    @Test func `filter set merge with multiple filters`() {
        // <=11, >9, !=10 — the classic carto test
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .lte, "11")) == nil)
        #expect(set.add(makeFilter("TOTAL", .gt, "9")) == nil)
        #expect(set.add(makeFilter("TOTAL", .neq, "10")) == nil)

        #expect(set.addable(makeFilter("TOTAL", .eq, "10")) == .conflict)
        #expect(set.addable(makeFilter("TOTAL", .eq, "10.5")) == .addable)
        #expect(set.addable(makeFilter("TOTAL", .eq, "9")) == .conflict)
        #expect(set.addable(makeFilter("TOTAL", .eq, "11")) == .addable)
        #expect(set.addable(makeFilter("TOTAL", .gt, "11")) == .conflict)
        #expect(set.addable(makeFilter("TOTAL", .gte, "11")) == .addable)
        #expect(set.addable(makeFilter("TOTAL", .lt, "11")) == .addable)
    }

    @Test func `filter set eq replaces all`() {
        // Adding foo= replaces every other filter on foo (carto's add).
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("A", .gt, "1")) == nil)
        #expect(set.add(makeFilter("A", .lt, "9")) == nil)
        #expect(set.add(makeFilter("A", .eq, "5")) == nil)
        #expect(set.filters.count == 1)
        #expect(set.filters["[A]="] != nil)
    }

    @Test func `filter set neq key includes value`() {
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("TOTAL", .neq, "11")) == nil)
        #expect(set.add(makeFilter("TOTAL", .neq, "9")) == nil)
        #expect(set.filters.count == 2)
    }

    @Test func `filter set to string order`() {
        var set: FilterSet = .init()
        #expect(set.add(makeFilter("B", .eq, "1")) == nil)
        #expect(set.add(makeFilter("A", .eq, "2")) == nil)
        #expect(set.idString == "[A]=2\t[B]=1")
    }

    // MARK: - Colors

    @Test func `color hex round trip`() {
        let color: Color = .init(h: 210, s: 0.5, l: 0.4)
        #expect(color.hexString == "#336699")
    }

    @Test func `color RGB conversion`() {
        let color: Color = .init(rgb: [51, 102, 153])
        #expect(color.hexString == "#336699")
        // lighten 20%
        let lighter: Color = .init(h: color.h, s: color.s, l: Color.clamp(color.l + 0.2))
        #expect(lighter.hexString == "#6699cc")
    }

    @Test func `color RGBA output`() {
        let color: Color = .init(rgb: [10, 20, 30], alpha: 0.5)
        #expect(color.serialized() == "rgba(10, 20, 30, 0.5)")
    }

    // MARK: - Zoom masks

    @Test func `zoom masks`() {
        #expect(Zoom.all == (1 << (Zoom.maxZoom + 1)) - 1)
        var messages = Messages()
        var evaluator: Evaluator = .init(env: ParserEnv(), messages: messages)
        #expect(
            Zoom.evaluate(
                op: .eq, value: .dimension(Dimension(value: 3, unit: nil)),
                evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil) == 8,
        )
        #expect(
            Zoom.evaluate(
                op: .gt, value: .dimension(Dimension(value: 2, unit: nil)),
                evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil) == 0b11_1111_1111_1111_1111_1111_1000,
        )
        #expect(
            Zoom.evaluate(
                op: .lte, value: .dimension(Dimension(value: 3, unit: nil)),
                evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil) == 0b1111,
        )
        #expect(
            // carto's parseInt semantics: 6.7 truncates to 6.
            Zoom.evaluate(
                op: .gte, value: .dimension(Dimension(value: 6.7, unit: nil)),
                evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil)
                == Zoom.rangeMask(start: 6, end: Zoom.maxZoom),
        )
    }

    @Test func `zoom conditions with variables`() {
        // carto's tree.Zoom.ev evaluates the value against env.frames.
        var messages = Messages()
        var evaluator: Evaluator = .init(env: ParserEnv(), messages: messages)
        let variable: Node = .variable(name: "@min_zoom", index: 0, filename: nil)
        evaluator.pushFrame([
            "@min_zoom": Rule(
                name: "@min_zoom", value: Value(values: [.dimension(Dimension(value: 6, unit: nil))]),
                index: 0, filename: nil),
        ])
        #expect(
            Zoom.evaluate(
                op: .gte, value: variable, evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil)
                == Zoom.rangeMask(start: 6, end: Zoom.maxZoom),
        )
        #expect(
            Zoom.evaluate(
                op: .eq, value: variable, evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil) == 1 << 6,
        )
        // Computed variables are evaluated too (carto: `6 - 1` → 5).
        let operation: Node = .operation(
            Operation(
                op: .subtract, lhs: .dimension(Dimension(value: 6, unit: nil)),
                rhs: .dimension(Dimension(value: 1, unit: nil))))
        #expect(
            Zoom.evaluate(
                op: .gt, value: operation, evaluator: &evaluator,
                messages: &messages, index: 0, filename: nil)
                == Zoom.rangeMask(start: 6, end: Zoom.maxZoom),
        )
        // Undefined variables produce an error message.
        let missing = Zoom.evaluate(
            op: .gte, value: .variable(name: "@nope", index: 0, filename: nil),
            evaluator: &evaluator, messages: &messages, index: 0, filename: nil)
        #expect(missing == 0)
        #expect(messages.items.contains { $0.message.contains("@nope is undefined") })
    }

    @Test func `zoom scale denominators`() {
        // zoom=3 → Max 100000000, Min 50000000
        var messages = Messages()
        var evaluator: Evaluator = .init(env: ParserEnv(), messages: messages)
        let mask = Zoom.evaluate(
            op: .eq, value: .dimension(Dimension(value: 3, unit: nil)),
            evaluator: &evaluator,
            messages: &messages, index: 0, filename: nil)
        let conditions = Zoom.scaleDenominators(zoom: mask).map { $0.0 + "=" + $0.1 }
        #expect(conditions == ["MaxScaleDenominator=100000000", "MinScaleDenominator=50000000"])
    }

    // MARK: - Number formatting (JavaScript Number.toString semantics)

    @Test func `number formatting`() {
        #expect(formatNumber(2) == "2")
        #expect(formatNumber(0.5) == "0.5")
        #expect(formatNumber(2.519833333333333) == "2.519833333333333")
        #expect(formatNumber(1e-7) == "1e-7")
        #expect(formatNumber(3.6e-5) == "0.000036")
        #expect(formatNumber(0.000036) == "0.000036")
        #expect(formatNumber(100_000_000) == "100000000")
    }

    // MARK: - Specificity sort

    @Test func `specificity order`() {
        func selector(_: String, conditions: Int, index: Int) -> Definition {
            var parserEnv: ParserEnv = .init(filename: "test.mss")
            parserEnv.inputs["test.mss"] = ""
            // phony selector
            let element: Element = .init(value: "#world")
            return Definition(
                selector: Selector(
                    elements: [element],
                    filters: FilterSet(),
                    zoom: Zoom.all,
                    zooms: [],
                    attachment: nil,
                    conditions: conditions,
                    index: index),
                rules: [])
        }

        // Higher conditions sort first; among equal conditions, higher index first.
        let highConditions = selector("a", conditions: 2, index: 0)
        let highIndex = selector("b", conditions: 1, index: 500)
        let lowIndex = selector("c", conditions: 1, index: 100)

        #expect(Compiler.specificitySort(highConditions, highIndex))
        #expect(!Compiler.specificitySort(highIndex, highConditions))
        #expect(Compiler.specificitySort(highIndex, lowIndex))
        #expect(!Compiler.specificitySort(lowIndex, highIndex))
    }

}
