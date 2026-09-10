# AGENTS.md

# swift-carto — CartoCSS → Mapnik XML compiler in Swift

A Swift port of Mapbox's archived [`carto`](https://github.com/mapbox/carto)
compiler (v1.2.2): it compiles [CartoCSS](https://cartocss.readthedocs.io/)
stylesheets (`.mss`) together with a TileMill project file (`project.mml`)
into Mapnik XML, for the `swift-mapnik`-based tile rendering pipeline.

It mirrors node carto's semantics **exactly**, including the quirky parts
(specificity sorting with descending source index, `filter-mode="first"`
folding, the JS string-comparison quirks in `Filterset.addable`, per-style
`existing` zoom bookkeeping shared across definitions, JavaScript
`Number.toString` formatting and `parseInt` semantics for attribute values).
When in doubt about any behavior, check the original at
`reference/carto/` (a local carto checkout — see *Differential tests*).

## Products

- **`Carto`** — the library target: CartoCSS lexer/parser, variable frames
  and color functions, mapnik-reference tables, style flattening/inheritance,
  and the Mapnik XML emitter.
- **`carto`** — the CLI executable (`Sources/CartoCLI/`), a drop-in
  replacement for node carto's command line (swift-argument-parser).

## Key source areas

```
Sources/Carto/
├── MML/              # project.mml loader (JSON/JSON5, stylesheet file resolution)
├── MSS/              # CartoCSS lexer/parser (chunked recursive descent,
│                     #   faithful port of carto's parser.js) + FilterSet
├── Eval/             # variable frames, color functions (less.js semantics),
│                     #   unit conversion (pt/pc/in/mm/cm/m → px @90.714 ppi)
├── Style/            # reference tables (mapnik-reference v3.0.22),
│                     #   flatten/specificity/inheritance (renderer.js),
│                     #   rule compilation (Definition.toObject)
├── XML/              # Mapnik XML emitter (carto's jsonToXML semantics)
└── Render.swift      # public façade: MML → Mapnik XML
Sources/CartoCLI/     # `carto project.mml > map.xml` drop-in CLI
Tests/CartoTests/     # Swift Testing: rendering fixtures + unit tests
tools/                # differential test harnesses against node carto
```

- **`Render.swift`** — `Renderer`, the central public entry point: loads
  stylesheets from an `MML` document, flattens and compiles the style
  definitions, and emits Mapnik XML. Ports carto's `renderer.js`
  (`inheritDefinitions`, `sortStyles`, `foldStyle`, `StyleObject`,
  `LayerObject`). Errors and warnings are collected as `Message` values;
  `render(_:)` returns `nil` when compilation produced errors.
- **`MSS/`** — the CartoCSS parser, a chunked recursive-descent port of
  carto's `parser.js`: input is split into chunks at top-level `}`
  boundaries (keeping strings, comments and `url(...)` groups intact), then
  consumed with backtracking. Also holds the AST (`AST.swift`, `Node.swift`),
  the `FilterSet` (carto's `tree.Filterset` simplification/conflict rules)
  and the zoom bitmask helpers (`Zoom.swift`, carto's `tree.Zoom`).
- **`Eval/Evaluator.swift`** — evaluates nodes against variable frames
  (carto's `ev(env)` chain). Frames hold variable name → `Rule`, innermost
  last. Also `Functions.swift` (color/builtin functions with less.js
  semantics) and `Color.swift`/`Color+Hex.swift` — `Color` carries the
  `perceptual` flag (carto's `tree.Color`), and the nested `Color.HSLuv`
  enum is a port of hsluv 0.0.2 (the reference implementation carto uses)
  for the perceptual color functions.
- **`Style/Compiler.swift`** — flattens parse trees into `Definition`s
  (nested rulesets multiply their parent selectors), applies inheritance,
  sorts styles and folds them. Also `RuleCompiler.swift` (carto's
  `Definition.toObject` zoom-splitting into `CompiledRule`s) and
  `Reference.swift` (vendored mapnik-reference v3.0.22 property tables).
- **`MML/MML.swift` + `JSONParser.swift`/`JSONValue.swift`/`YAMLParser.swift`** — parses
  `project.mml` as JSON/JSON5, resolves `@style.mss` references against
  `basedir`, keeps unknown members in `rawMembers` for pass-through. YAML
  project files are supported through the `EnableYAMLProjectFiles` package
  trait (`YAMLParser` bridges Yams' node trees to `JSONValue`, mirroring
  js-yaml 3.x scalar semantics: only true/false booleans, octal/hex/
  sexagesimal integers, merge keys, duplicate keys rejected). Layer
  datasources pass through verbatim — no millstone localization, no
  downloading of remote resources.
- **`CartoCLI/CartoCLI.swift`** — argument-parser CLI mirroring node carto's
  options (`-q`, `-b`, `--ppi`, `-a`, `-f`, `--output`).

## Faithfulness rules

When changing or extending compiler behavior, **first check what node carto
does** — the reference checkout lives at `reference/carto/`:

- `reference/carto/lib/carto/renderer.js` — render pipeline, inheritance,
  style sorting/folding
- `reference/carto/lib/carto/tree/*.js` — per-node-type semantics
  (`zoom.js`, `definition.js`, `ruleset.js`, `filterset.js`, …)
- `reference/carto/lib/carto/parser.js` — grammar and error messages
- `reference/carto/test/rendering/` — the rendering corpus (the fixtures in
  `Tests/CartoTests/Fixtures` come from here, Apache-2.0)
- `reference/carto/test/rendering-mss/` — MSS-only corpus
  (`renderMSS` debug API, which this port does not implement as an API, but
  whose expectations make good fixtures)

Error and warning messages should match carto's verbatim (they are part of
the API surface, and tests assert on them).

## Dependencies

- **swift-argument-parser** 1.8.2+ — CLI only. With the `EnableYAMLProjectFiles`
  package trait (**opt-in**, see `Package.swift`), **Yams** is also a dependency
  of the `Carto` library target; by default the library has **no external
  dependencies**. YAML-specific code is guarded with
  `#if EnableYAMLProjectFiles` — both trait states must build and test green:
  `swift test` (trait off) and `swift test --traits EnableYAMLProjectFiles`.
  Note: traits can only be enabled from the CLI; there is no reliable opt-out
  from a default trait, which is why YAML support is opt-in.

## Build & test

Builds on macOS (≥ macOS 15) and Linux with Swift 6.3+:

```bash
swift build           # build library + CLI
swift test            # run tests (Swift Testing): rendering fixtures + unit tests
```

In the development container `CC` defaults to `gcc`, which rejects Swift's
`-target`/`-fblocks` flags — use the toolchain's clang for Yams' C sources:
`CC=clang CXX=clang++ swift build`.

### Differential tests

The differential harnesses compare this port against node carto directly.
They require a local carto checkout with its dependencies installed:

```bash
git clone https://github.com/mapbox/carto reference/carto \
  && (cd reference/carto && npm install)
node tools/run_rendering_corpus.js    # 82/82 fixtures must pass
```

The checkout location can be overridden with the `CARTO_REFERENCE`,
`CARTO_BIN` and `CARTO_PROJECTS` environment variables — see the scripts in
`tools/` for details.

When changing compiler behavior, also verify new/changed semantics directly
against node carto (a small `node -e` script with
`new carto.Renderer(...).render(mml)` against `reference/carto` is usually
the fastest way to pin down carto's exact output, error messages included).

## Swift instructions

- DO USE idiomatic Swift 6
- DO write tests for everything you do, use Swift Testing (`import Testing`), not XCTest
- DO ASK if anything is unclear, or you need a decision
- DO add proper Swift DocC code documentation to your code
- DO NOT introduce third-party frameworks without asking first (the library
  target intentionally has zero dependencies)
- AVOID force unwraps and force `try` unless it is unrecoverable
- Assume strict Swift concurrency rules are being applied (`Renderer` is a
  `Sendable`-friendly value type)

## Code style conventions

4-space indentation, no tabs, DocC documentation, Swift 6 concurrency,
`Sendable` conformance on all model types. Formatting is enforced with
[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (`.swiftformat`
in the repo root): run `swiftformat Sources Tests --swift-version 6.3`
before finishing. Key rules:

### Spacing

- 4-space indentation, no tabs
- Commas: Left-hugging, space follows. `x, y`
- Binary operators: single-space padding before and after. `a + (b * c)`
- Return arrow tokens: Spaces on both sides. `f() -> T`
- Ranges: spaces on both sides. `1 ... 3`
- Trailing closure: space before opening brace. `function() { ... }`
- Comments: space between delimiters and text. `// comment`
- Trailing whitespace: Never.

### General

- Multiple `if` conditions separated by `,`, not `&&`. `if a == 1, b == 2 {}`
- Use `isNotEmpty` instead of `!isEmpty`
- Left-hugging colons with space after. `let x: [String: String]`
- `struct` by default, `class` only when needed, `actor` for mutable shared state
- `Sendable` conformance on all model types
- `guard let` / `if let` with early returns
- `// MARK:` and `// MARK: -` to organize extensions
- `PascalCase` for types, `camelCase` for everything else
- Put `else` on its own line

## Repository extras

- `reference/` — local checkouts used for differential testing and semantic
  lookups: `carto/` (the original node.js compiler), `mapnik-ref/`,
  `magnacarto/`. Not part of the package; never build them or commit to them.
- `tools/` — node.js differential test harnesses (see above).
- The test fixtures in `Tests/CartoTests/Fixtures/` (`.mml` + `.mss` +
  `.result` triples) come from carto's rendering corpus; the `.result` files
  are the XML trees Swift Testing compares against (formatting/CDATA
  differences are ignored, element order/attributes/text must match).