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

    // MARK: - HSLuv perceptual colors (verified against node carto + hsluv 0.0.2)

    @Test func `hsluv conversions`() {
        // hsluv 0.0.2 reference values: hsluvToRgb([262.9, 100, 75]) with
        // S/L on the 0–100 scale.
        let inGamut = Color.HSLuv.hsluvToRGB([262.9, 100, 75]).map { $0 * 255 }
        #expect(abs(inGamut[0] - 171.73265032) < 0.000001)
        #expect(abs(inGamut[1] - 179.19456988) < 0.000001)
        #expect(abs(inGamut[2] - 255.00000158) < 0.00001)

        let back = Color.HSLuv.rgbToHSLuv([0.5, 0.6, 0.7])
        #expect(abs(back[0] - 239.73887065827515) < 0.000001)
        #expect(abs(back[1] - 34.41572153960916) < 0.000001)
        #expect(abs(back[2] - 62.1403505996297) < 0.000001)
    }

    @Test func `perceptual color round trips`() {
        let standard: Color = .init(h: 210, s: 0.5, l: 0.4)
        let perceptual = standard.toPerceptual()
        #expect(perceptual.perceptual)
        let back = perceptual.toStandard()
        #expect(!back.perceptual)
        // Round-trip through RGB should land on the same color.
        #expect(back.hexString == standard.hexString)
    }

    @Test func `perceptual color functions`() {
        // Expected values from node carto 1.2.2 (chroma-js + hsluv 0.0.2).
        let base: Color = .init(rgb: [51, 102, 153]) // #336699

        func renderColor(_ expression: String) -> String {
            let mss = "#world { line-color: \(expression); }"
            var env: ParserEnv = .init(filename: "test.mss")
            env.inputs["test.mss"] = mss
            guard let root = try? MSSParser.parse(mss, env: env) else { return "PARSE ERROR" }

            var localMessages = Messages()
            var evaluator: Evaluator = .init(env: env, messages: localMessages)
            var compiler = Compiler(evaluator: evaluator)
            guard let definitions = try? compiler.flatten([root]) else { return "FLATTEN ERROR" }

            var ruleCompiler = RuleCompiler(evaluator: compiler.evaluator)
            var existing: [String: Int] = [:]
            var color: Color?
            for definition in definitions {
                for compiled in ruleCompiler.compile(definition, existing: &existing) {
                    for (_, properties) in compiled.symbolizers {
                        for (_, rule) in properties {
                            let evaluated = evaluator.evaluateValue(rule.value)
                            if case let .color(c) = evaluated {
                                color = c
                            }
                        }
                    }
                }
            }
            return color?.serialized() ?? "ERROR"
        }

        #expect(renderColor("hsluv(262.9, 1, 0.75)") == "#acb3ff")
        #expect(renderColor("hsluv(262.9, 100, 75)") == "#ffffff") // clamped to s=l=1
        #expect(renderColor("hsluva(262.9, 1, 0.75, 0.5)") == "rgba(172, 179, 255, 0.5)")
        #expect(renderColor("lightenp(#336699, 10)") == "#4180be")
        #expect(renderColor("darkenp(#336699, 10)") == "#254e76")
        #expect(renderColor("saturatep(#336699, 20)") == "#0867a6")
        #expect(renderColor("desaturatep(#336699, 20)") == "#45658c")
        #expect(renderColor("fadeinp(#336699, 30)") == "#336699")
        #expect(renderColor("fadeoutp(#336699, 30)") == "rgba(51, 102, 153, 0.7)")
        #expect(renderColor("spinp(#336699, 45)") == "#9437b6")
        #expect(renderColor("greyscalep(#336699)") == "#636363")
        #expect(renderColor("huep(#336699)") == "ERROR") // dimension, not color
        #expect(renderColor("lightnessp(#336699)") == "ERROR") // dimension, not color
        #expect(renderColor("mix(#336699, hsluv(100, 50, 50), 50)") == "#99b3cc")

        _ = base // documented input color
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

    // MARK: - YAML project files (carto's js-yaml semantics)

    #if EnableYAMLProjectFiles
    @Test func `yaml scalars`() throws {
        // js-yaml 3.x (carto's parser) semantics: only true/false are
        // booleans; yes/no/on/off stay strings.
        let yaml = """
        a: plain string
        quoted: 'single quoted'
        int: 42
        octal: 010
        hex: 0x1F
        float: 1.5
        exponent: 1e3
        true_bool: true
        false_bool: FALSE
        yes_string: yes
        on_string: on
        null_tilde: ~
        null_word: null
        empty:
        """
        let value = try YAMLParser.parse(yaml)
        let object = try #require(value.objectValue)
        let keys = object.map(\.0)
        #expect(keys == [
            "a", "quoted", "int", "octal", "hex", "float", "exponent",
            "true_bool", "false_bool", "yes_string", "on_string",
            "null_tilde", "null_word", "empty",
        ])
        #expect(try #require(object.first { $0.0 == "a" }).1 == .string("plain string"))
        #expect(try #require(object.first { $0.0 == "quoted" }).1 == .string("single quoted"))
        #expect(try #require(object.first { $0.0 == "int" }).1 == .number(42))
        #expect(try #require(object.first { $0.0 == "octal" }).1 == .number(8))
        #expect(try #require(object.first { $0.0 == "hex" }).1 == .number(31))
        #expect(try #require(object.first { $0.0 == "float" }).1 == .number(1.5))
        #expect(try #require(object.first { $0.0 == "exponent" }).1 == .number(1000))
        #expect(try #require(object.first { $0.0 == "true_bool" }).1 == .bool(true))
        #expect(try #require(object.first { $0.0 == "false_bool" }).1 == .bool(false))
        #expect(try #require(object.first { $0.0 == "yes_string" }).1 == .string("yes"))
        #expect(try #require(object.first { $0.0 == "on_string" }).1 == .string("on"))
        #expect(try #require(object.first { $0.0 == "null_tilde" }).1 == .null)
        #expect(try #require(object.first { $0.0 == "null_word" }).1 == .null)
        #expect(try #require(object.first { $0.0 == "empty" }).1 == .null)
    }

    @Test func `yaml anchors aliases and merge keys`() throws {
        let yaml = """
        base: &base
          type: shape
          file: common.shp
        merged:
          <<: *base
          file: specific.shp
        merged_list:
          <<: [*base, *base]
        alias_array: *base
        """
        let value = try YAMLParser.parse(yaml)
        let object = try #require(value.objectValue)

        let merged = try #require(object.first { $0.0 == "merged" }).1
        #expect(merged["type"] == .string("shape"))
        // Explicit keys win over merge keys.
        #expect(merged["file"] == .string("specific.shp"))

        let aliasArray = try #require(object.first { $0.0 == "alias_array" }).1
        #expect(aliasArray["file"] == .string("common.shp"))
    }

    @Test func `yaml duplicate keys error`() {
        // Yams' composer reports duplicate keys (js-yaml does the same).
        #expect(throws: (any Error).self) {
            _ = try YAMLParser.parse("a: 1\na: 2\n")
        }
    }

    @Test func `yaml int scalars`() {
        #expect(YAMLParser.parseInt("42") == 42)
        #expect(YAMLParser.parseInt("+12") == 12)
        #expect(YAMLParser.parseInt("-010") == -8)
        #expect(YAMLParser.parseInt("0x1F") == 31)
        #expect(YAMLParser.parseInt("0b101") == 5)
        #expect(YAMLParser.parseInt("1_000") == 1000)
        // js-yaml's sexagesimal integers.
        #expect(YAMLParser.parseInt("1:30") == 90)
        #expect(YAMLParser.parseInt("-1:30") == -90)
        #expect(YAMLParser.parseInt("abc") == nil)
        #expect(YAMLParser.parseInt("") == nil)
    }

    @Test func `yaml mml loads and resolves stylesheets`() throws {
        // The zoomselector_yaml fixture loads the same project as its JSON twin.
        let fixtureURL = Bundle.module.bundleURL.appendingPathComponent("Fixtures", isDirectory: true)
        let mmlData = try String(
            contentsOf: fixtureURL.appendingPathComponent("zoomselector_yaml.mml"), encoding: .utf8)
        let mml = try MML(data: mmlData, basedir: fixtureURL)
        #expect(mml.stylesheets.map(\.id) == ["zoomselector_yaml.mss"])
        #expect(mml.layers.map(\.id) == ["world"])
        #expect(mml.srs?.hasPrefix("+proj=merc") == true)
    }
    #endif

}
