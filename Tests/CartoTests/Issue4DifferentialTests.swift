@testable import Carto
import Foundation
import Testing

/// Differential tests for rule ordering with comma-separated selectors
/// (issue #4): the `<Style>` blocks must match node carto 1.2.2's output
/// for the same MML input.
struct Issue4DifferentialTests {

    @Test(arguments: [
        "comma_zoom_filters", "comma_same_zoom", "comma_reversed",
        "three_selectors", "nested_shared", "filter_overlap",
        "same_selector_twice",
    ])
    func `ordering matches node carto`(_ name: String) throws {
        let cases: [String: (mss: String, styles: String)] = [
            "comma_zoom_filters": (
                "#world[zoom >= 5][foo = 1], #world[zoom >= 3][bar = 2] { line-color: #f00; line-width: 1; }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <MaxScaleDenominator>25000000</MaxScaleDenominator>
                    <Filter><![CDATA[([foo] = 1) and ([bar] = 2)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" stroke-width="1" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>100000000</MaxScaleDenominator>
                    <MinScaleDenominator>25000000</MinScaleDenominator>
                    <Filter><![CDATA[([foo] = 1) and ([bar] = 2)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" stroke-width="1" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>25000000</MaxScaleDenominator>
                    <Filter><![CDATA[([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" stroke-width="1" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>100000000</MaxScaleDenominator>
                    <Filter><![CDATA[([bar] = 2)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" stroke-width="1" />
                  </Rule>
                </Style>
                """,
            ),
            "comma_same_zoom": (
                "#world[foo = 1], #world[bar = 2] { line-color: #f00; }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <Filter><![CDATA[([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                  <Rule>
                    <Filter><![CDATA[([bar] = 2)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                </Style>
                """,
            ),
            "comma_reversed": (
                "#world[zoom < 3][bar = 2], #world[zoom < 5][foo = 1] { line-color: #f00; }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <MinScaleDenominator>100000000</MinScaleDenominator>
                    <Filter><![CDATA[([bar] = 2) and ([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>100000000</MaxScaleDenominator>
                    <MinScaleDenominator>25000000</MinScaleDenominator>
                    <Filter><![CDATA[([bar] = 2) and ([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                  <Rule>
                    <MinScaleDenominator>100000000</MinScaleDenominator>
                    <Filter><![CDATA[([bar] = 2)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                  <Rule>
                    <MinScaleDenominator>25000000</MinScaleDenominator>
                    <Filter><![CDATA[([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                </Style>
                """,
            ),
            "three_selectors": (
                "#world[zoom = 1], #world[zoom = 3], #world[zoom = 2] { line-width: 1; }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <MaxScaleDenominator>500000000</MaxScaleDenominator>
                    <MinScaleDenominator>200000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="1" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>100000000</MaxScaleDenominator>
                    <MinScaleDenominator>50000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="1" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>200000000</MaxScaleDenominator>
                    <MinScaleDenominator>100000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="1" />
                  </Rule>
                </Style>
                """,
            ),
            "nested_shared": (
                "#world { [zoom=1] { line-width:2; } [zoom=2] { line-width:1.5; } [zoom=3], [zoom=4] { line-width:1.25; } }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <MaxScaleDenominator>50000000</MaxScaleDenominator>
                    <MinScaleDenominator>25000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="1.25" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>100000000</MaxScaleDenominator>
                    <MinScaleDenominator>50000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="1.25" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>200000000</MaxScaleDenominator>
                    <MinScaleDenominator>100000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="1.5" />
                  </Rule>
                  <Rule>
                    <MaxScaleDenominator>500000000</MaxScaleDenominator>
                    <MinScaleDenominator>200000000</MinScaleDenominator>
                    <LineSymbolizer stroke-width="2" />
                  </Rule>
                </Style>
                """,
            ),
            "filter_overlap": (
                "#world[foo = 1], #world[foo = 1][bar = 2] { line-color: #f00; }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <Filter><![CDATA[([foo] = 1) and ([bar] = 2)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                  <Rule>
                    <Filter><![CDATA[([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                </Style>
                """,
            ),
            "same_selector_twice": (
                "#world[foo = 1], #world[foo = 1] { line-color: #f00; }",
                """
                <Style filter-mode="first" name="world">
                  <Rule>
                    <Filter><![CDATA[([foo] = 1)]]></Filter>
                    <LineSymbolizer stroke="#ff0000" />
                  </Rule>
                </Style>
                """,
            ),
        ]

        let testCase = try #require(cases[name])
        let mssJSON = try #require(String(
            data: JSONSerialization.data(withJSONObject: [testCase.mss]), encoding: .utf8)?
            .dropFirst()
            .dropLast())
        let mmlJSON =
            "{\"srs\": \"+proj=merc\", \"Stylesheet\": [{\"id\": \"s.mss\", \"data\": "
                + mssJSON + "}], \"Layer\": [{\"id\": \"world\"}]}"
        let mml = try MML(data: mmlJSON, basedir: nil)
        var renderer = Renderer()
        let xml = try #require(
            renderer.render(mml),

            "\(name): render failed: \(renderer.messages.map(\.description).joined(separator: "; "))")

        #expect(
            Self.stylesBlock(xml) == Self.normalized(testCase.styles),
            "\(name): rule ordering mismatch",
        )
    }

    /// Whitespace-normalized multi-line string.
    private static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The `<Style>…</Style>` blocks of the XML, whitespace-normalized.
    private static func stylesBlock(_ xml: String) -> String {
        var output: [String] = []
        var inside = false
        for line in xml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<Style ") || trimmed.hasPrefix("<Style>") {
                inside = true
            }
            if inside {
                output.append(trimmed)
            }
            if trimmed == "</Style>" {
                inside = false
            }
        }
        return normalized(output.joined(separator: "\n"))
    }
}
