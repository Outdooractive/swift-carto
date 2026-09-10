[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fswift-carto%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/swift-carto)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fswift-carto%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/swift-carto)
[![](https://img.shields.io/github/license/Outdooractive/swift-carto)](https://github.com/Outdooractive/swift-carto/blob/main/LICENSE)
[![](https://img.shields.io/github/v/release/Outdooractive/swift-carto?sort=semver&display_name=tag)](https://github.com/Outdooractive/swift-carto/releases) [![](https://img.shields.io/github/release-date/Outdooractive/swift-carto?display_date=published_at)](https://github.com/Outdooractive/swift-carto/releases)
[![](https://img.shields.io/github/issues/Outdooractive/swift-carto)](https://github.com/Outdooractive/swift-carto/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/swift-carto)](https://github.com/Outdooractive/swift-carto/pulls)
[![](https://img.shields.io/github/check-runs/Outdooractive/swift-carto/main)](https://github.com/Outdooractive/swift-carto/actions)

# Carto

A Swift port of Mapbox's archived [`carto`](https://github.com/mapbox/carto) compiler: it compiles [CartoCSS](https://cartocss.readthedocs.io/) stylesheets (`.mss`) together with a TileMill project file (`project.mml`) into Mapnik XML, for the `swift-mapnik`-based tile rendering pipeline.

## Table of Contents

- [Carto](#carto)
  - [Features](#features)
  - [Notes](#notes)
  - [Requirements](#requirements)
  - [Package traits](#package-traits)
  - [Installation with Swift Package Manager](#installation-with-swift-package-manager)
  - [Quick start](#quick-start)
- [The Renderer API](#the-renderer-api)
- [Loading MML project files](#loading-mml-project-files)
- [Compile messages](#compile-messages)
- [The carto CLI](#the-carto-cli)
  - [Supported flags](#supported-flags)
- [Package layout](#package-layout)
- [Behavior notes](#behavior-notes)
- [Missing or partial CartoCSS features](#missing-or-partial-cartocss-features)
  - [Missing](#missing)
  - [Partial](#partial)
  - [Out of scope by design](#out-of-scope-by-design)
- [Tests](#tests)
- [Acknowledgments](#acknowledgments)
- [Related packages](#related-packages)
- [Contributing](#contributing)
- [License](#license)
- [Authors](#authors)

## Features

- Faithful port of carto 1.2.2, verified against carto's own rendering corpus (82/82 fixtures)
- CartoCSS lexer/parser — a faithful port of carto's `parser.js`, as a chunked recursive descent parser
- Variable frames and color functions with less.js semantics, including hex, RGB(A) and HSL output
- Unit conversion for `m`, `mm`, `cm`, `in`, `pt` and `pc` to pixels at 90.714 ppi (carto's default)
- mapnik-reference v3.0.22 property tables: validation, defaults, and per-property status
- Style flattening with specificity sorting, inheritance and per-style zoom bookkeeping (carto's `renderer.js`)
- Rule compilation to Mapnik XML with carto's `jsonToXML` semantics, including `filter-mode="first"` folding
- MML loader for JSON/JSON5 project files with stylesheet file resolution (YAML project files via the opt-in `EnableYAMLProjectFiles` trait)
- `Renderer` is a `Sendable`-friendly value type; compile errors and warnings are returned as `Message` values
- A drop-in `carto` CLI mirroring node carto's command line options

## Notes

This package intentionally mirrors node carto 1.2.2's semantics exactly, including the quirky parts: specificity sorting with descending source index, `filter-mode="first"` folding, the JS string-comparison quirks in `Filterset.addable`, per-style `existing` zoom bookkeeping shared across definitions, and JavaScript `Number.toString` formatting for attribute values.

- Only Mapnik XML output is produced; `-o json` output and carto's `renderMSS` debug API are not implemented.
- Only mapnik-reference v3.0.22 semantics (node carto's default) are built in; per-version differences are not switchable.
- `project.mml` is parsed as JSON/JSON5; YAML project files are supported through the opt-in `EnableYAMLProjectFiles` package trait (see *Package traits* below).
- Millstone resource localization never happens here — datasources pass through verbatim.

## Requirements

This package requires Swift 6.3 or higher, and compiles on macOS (\>= macOS 15) and Linux. By default it has no external dependencies besides [swift-argument-parser][2] (used by the CLI only); enabling the `EnableYAMLProjectFiles` trait additionally pulls in [Yams][14].

## Package traits

- `EnableYAMLProjectFiles` — enables YAML (`.yaml`/`.yml`) project file parsing in the MML loader. **Opt-in** (SwiftPM traits can only be turned *off* from their default state, so YAML support is not on by default). When enabled, [Yams][14] is pulled in and `MML.init(data:basedir:)` falls back to YAML when JSON/JSON5 parsing fails (mirroring carto, which pipes every project file through `js-yaml`).

```swift
// Enable the trait for your target:
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Carto", package: "swift-carto"),
    ],
    traits: ["EnableYAMLProjectFiles"]),
```

```sh
swift build --traits EnableYAMLProjectFiles    # build/CLI with YAML support
swift test --traits EnableYAMLProjectFiles     # tests including the YAML fixtures
```

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/swift-carto", from: "1.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "Carto", package: "swift-carto"),
    ]),
]
```

## Quick start

```swift
import Carto
import Foundation

// Load a TileMill project file; stylesheets are resolved relative to `basedir`
let mml = try MML(
    data: try String(contentsOf: projectURL, encoding: .utf8),
    basedir: projectURL.deletingLastPathComponent())

// Render to Mapnik XML
var renderer = Renderer()
if let xml = renderer.render(mml) {
    print(xml)
}
else {
    for message in renderer.messages where message.kind == .error {
        print(message)
    }
}
```

Stylesheets can also be embedded directly in the project file as `{ id: 'style.mss', data: '...' }` objects instead of file references, in which case `basedir` isn't needed.

See the [tests for more examples][3].

# The Renderer API

[Implementation][4]

`Renderer` is the central entry point: it loads stylesheets from an `MML` document, flattens and compiles the style definitions, and emits Mapnik XML:
```swift
/// Compile messages (errors/warnings) from the last render.
public private(set) var messages: [Message] = []

/// - Parameter ppi: Pixels per inch for unit conversion; carto's
///   default (and the CLI default) is 90.714.
public init(ppi: Double = 90.714)

/// Render an MML document (loaded stylesheets) to Mapnik XML.
/// Returns `nil` when compilation produced errors (messages carry the
/// details).
public mutating func render(_ mml: MML) -> String?
```

The render pipeline follows carto's `Render.js`: every stylesheet is parsed into an AST (variables are shared across stylesheets, carto passes the environment between them), definitions are flattened with specificity sorting and inheritance, validated against the mapnik-reference tables, and finally serialized to Mapnik XML.

# Loading MML project files

[Implementation][5]

`MML` represents a TileMill project (`project.mml`), with its stylesheets, layers and global properties:
```swift
public struct MML: Sendable {
    public struct Stylesheet: Sendable {
        public let id: String
        public let data: String
        public init(id: String, data: String)
    }

    public struct Layer: Sendable {
        public struct Datasource: Sendable {
            public var values: [(String, JSONValue)]
            public init(values: [(String, JSONValue)])
        }

        public let id: String
        public var name: String?
        public var classes: [String]
        public var srs: String?
        public var status: String?
        public var geometry: String?
        public var extent: [Double]?
        public var properties: [(String, JSONValue)]?
        public var datasource: Datasource?
        public var extra: [String: JSONValue]
        public init(json: JSONValue) throws
    }

    public var name: String?
    public var description: String?
    public var attribution: String?
    public var bounds: JSONValue?
    public var center: JSONValue?
    public var format: String?
    public var minzoom: Int?
    public var maxzoom: Int?
    public var srs: String?
    public var interactivity: JSONValue?
    public var scale: Double?
    public var metatile: Int?
    public var bufferSize: Int?
    public var stylesheets: [Stylesheet]
    public var layers: [Layer]
    public var parameters: [String: JSONValue]
    public var rawMembers: [(String, JSONValue)]?
    public var globalProperties: [String: [(String, JSONValue)]]

    /// Parse a project file (JSON/JSON5) and resolve its stylesheet
    /// references relative to `basedir`.
    public init(data: String, basedir: URL?) throws
}
```

`MML(data:basedir:)` parses the project file, resolves `@style.mss` references against `basedir`, and collects carto's global properties (`Map`, `_labels` and friends). Unknown members are kept in `rawMembers` and passed through to the XML emitter.

Layer datasources pass through verbatim — no millstone localization, no downloading of remote resources.

# Compile messages

[Implementation][6]

Compilation reports errors and warnings as `Message` values, mirroring carto's messages:
```swift
public struct CartoError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String)
    public var description: String { message }
}

public struct Message: Sendable, Equatable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        case error
        case warning
    }

    public let kind: Kind
    public let message: String
    public let filename: String?
    public let line: Int
}
```

Example:
```swift
var renderer = Renderer(ppi: 96)
if renderer.render(mml) == nil {
    for message in renderer.messages where message.kind == .error {
        print(message.filename ?? "-", message.line, message.message)
    }
}
```

# The carto CLI

[Implementation][7]

The `CartoCLI` target builds a `carto` executable that is a drop-in replacement for node carto's CLI (ArgumentParser, mirroring node carto's options):
```sh
carto project.mml > map.xml
carto -f map.xml -q project.mml   # quiet, write to file
carto --ppi 96 project.mml        # unit conversion ppi (default: 90.714)
carto -b project.mml              # print total compile time
carto --help
```

## Supported flags

- `-q/--quiet` — do not output any warnings
- `-b/--benchmark` — output the total compile time
- `--ppi` — pixels per inch for unit conversion (default: 90.714)
- `-a/--api` — Mapnik API version (only 3.0.x semantics are supported)
- `-f/--file` — output to the specified file instead of stdout
- `--output mapnik` — output format (only `mapnik`; JSON output is not supported)
- `-l/--localize` and `-n/--nosymlink` — rejected/no-op (millstone is not part of this port)

# Package layout

```
Sources/Carto/
├── MML/              # project.mml loader (JSON5, Stylesheet file resolution)
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

# Behavior notes

The port follows carto 1.2.2's semantics exactly, including the quirky parts (see [Notes](#notes)).

# Missing or partial CartoCSS features

The port covers most the CartoCSS surface and was verified against carto's own rendering corpus (82/82). Features that node carto 1.2.2 supports but this port does not (or only partially):

## Missing

- **mapnik-reference version selection** (`--api`): only v3.0.22 semantics are built in (node carto's default). Per-version differences (e.g. `maxzoom` vs `minimum-scale-denominator` layer attributes, filter keyword lists) are not switchable.
- **`-o json` output** and the `Renderer.renderMSS` debug API: only Mapnik XML is produced.
- **"Did you mean …?" suggestions**: unrecognized rules/functions produce the error without carto's edit-distance suggestion.
- **Status warnings**: `deprecated`/`unstable`/`experimental` property statuses are in the reference tables but no warnings are emitted.

## Partial

- **Perceptual color functions**: `hsluv()`, `hsluva()` and the `*p` variants (`lightenp`, `darkenp`, `saturatep`, `desaturatep`, `fadeinp`, `fadeoutp`, `spinp`, `greyscalep`, `huep`, `saturationp`, `lightnessp`) fall back to plain HSL math instead of the HSLuv perceptual color space.
- **Value-type validation**: carto's `validValue` checks the declared type of every property value; this port validates `unsigned` (rounding), font values, keyword options, filter keywords and required properties, but lets most other value types through unvalidated.
- **`colorize-alpha()`**: passes through as an image-filter call without argument validation (carto validates against the reference).
- **Geometry-transform functions** (`matrix`, `translate`, `scale`, `rotate`, `skewX`, `skewY`): serialized verbatim; argument counts are not validated.

**Known limitation** (see below): rule ordering for comma-separated selectors with different zoom+filter pairs sharing one block can differ from node carto.

## Out of scope by design

- Millstone resource localization (carto's `-l/--localize`): downloading and localizing remote datasource files never happens here — datasources pass through verbatim.
- Custom user-supplied references (`Renderer({ reference })`).

# Tests

```sh
swift test                                # fixtures + unit tests (no YAML)
swift test --traits EnableYAMLProjectFiles  # include the YAML fixture tests
node tools/run_rendering_corpus.js        # differential test vs node carto
                                          # (requires a local carto checkout)
```

The rendering fixtures in `Tests/CartoTests/Fixtures` come from carto's `test/rendering` corpus (Apache-2.0). The unit tests are ported from carto's own test suites (`filterset.test.js`, `color.test.js`, zoom and specificity tests).

The differential test harnesses in `tools/` compare this port against node carto directly. They require a local carto checkout with its dependencies installed (`git clone https://github.com/mapbox/carto reference/carto && (cd reference/carto && npm install)`); the checkout location and other paths can be overridden with the `CARTO_REFERENCE`, `CARTO_BIN` and `CARTO_PROJECTS` environment variables — see the scripts for details.

# Acknowledgments

This package is MIT licensed and builds on third-party components with compatible licenses:

| Component | License | How it is used |
| --------- | ------- | -------------- |
| Component | License | How it is used |
| --------- | ------- | -------------- |
| [carto][8] | Apache-2.0 | The original node.js compiler this package ports; also the source of the rendering test corpus |
| [mapnik-reference][9] | Apache-2.0 | Property tables (v3.0.22), vendored into `Sources/Carto/Style` |
| [less.js][10] | Apache-2.0 | Color function semantics, reimplemented in Swift |
| [Yams][14] | MIT | YAML project file parsing (with the `EnableYAMLProjectFiles` trait) |

# Related packages

- [swift-stb-image][11]: Swift wrapper around stb_image/stb_image_write and libwebp for reading and writing PNG, JPG and WebP images
- [gis-tools][12]: GIS tools for Swift, including a GeoJSON implementation and many algorithms
- [mvt-tools][13]: Vector tiles reader/writer for Swift

# Contributing

Please [create an issue](https://github.com/Outdooractive/swift-carto/issues) or [open a pull request](https://github.com/Outdooractive/swift-carto/pulls) with a fix or enhancement.

# License

MIT

# Authors

Thomas Rasch, Outdooractive

[1]: https://github.com/mapbox/carto "carto"
[2]: https://github.com/apple/swift-argument-parser "swift-argument-parser"
[3]: https://github.com/Outdooractive/swift-carto/tree/main/Tests/CartoTests "Tests"
[4]: https://github.com/Outdooractive/swift-carto/blob/main/Sources/Carto/Render.swift "Render.swift"
[5]: https://github.com/Outdooractive/swift-carto/blob/main/Sources/Carto/MML/MML.swift "MML.swift"
[6]: https://github.com/Outdooractive/swift-carto/blob/main/Sources/Carto/Messages.swift "Messages.swift"
[7]: https://github.com/Outdooractive/swift-carto/blob/main/Sources/CartoCLI/CartoCLI.swift "CartoCLI.swift"
[8]: https://github.com/mapbox/carto "carto"
[9]: https://github.com/mapbox/mapnik-reference "mapnik-reference"
[10]: https://github.com/less/less.js "less.js"
[11]: https://github.com/Outdooractive/swift-stb-image "swift-stb-image"
[12]: https://github.com/Outdooractive/gis-tools "gis-tools"
[13]: https://github.com/Outdooractive/mvt-tools "mvt-tools"
[14]: https://github.com/jpsim/Yams "Yams"
