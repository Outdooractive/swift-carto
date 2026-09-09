//
//  Created by Thomas Rasch, 2026.
//

import ArgumentParser
import Carto
import Foundation

/// The main entry point for the `carto` command line tool.
///
/// Compiles CartoCSS stylesheets (`.mss`) and a TileMill project file
/// (`project.mml`) into Mapnik XML — a Swift port of Mapbox's archived
/// node.js `carto` compiler.
@main
struct CartoCLI: ParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "carto",
        abstract: "Compile CartoCSS stylesheets into Mapnik XML.",
        discussion: """
        Compiles a TileMill project (project.mml with its referenced .mss
        stylesheets) into Mapnik XML, mirroring the behavior of Mapbox's
        archived node.js 'carto' compiler.

        Examples:
        - /Users/you/TilemillProjects/topo_bkg/project.mml
        """,
        version: cliVersion)

    @Argument(
        help: "The project file (project.mml).",
        completion: .file(extensions: ["mml", "json", "yaml", "yml"]),
    )
    var projectFile: String

    @Flag(
        name: .shortAndLong,
        help: "Do not output any warnings.",
    )
    var quiet = false

    @Flag(
        name: .shortAndLong,
        help: "Output the total compile time.",
    )
    var benchmark = false

    @Option(
        name: .customLong("ppi"),
        help: "Pixels per inch used to convert m, mm, cm, in, pt, pc to pixels (default: 90.714).",
    )
    var ppi: Double = 90.714

    @Option(
        name: .shortAndLong,
        help: "Mapnik API version (only 3.0.x semantics are supported).",
    )
    var api: String?

    @Option(
        name: [.customShort("f"), .customLong("file")],
        help: "Output to the specified file instead of stdout.",
    )
    var outputFile: String?

    @Option(
        name: .customLong("output"),
        help: "Output format ('mapnik'; JSON output is not supported by this port).",
    )
    var output = "mapnik"

    @Flag(
        name: .shortAndLong,
        help: "Use millstone to localize resources (not supported by this port).",
    )
    var localize = false

    @Flag(
        name: .shortAndLong,
        help: "Use absolute paths instead of symlinking files (this port never symlinks).",
    )
    var nosymlink = false

    mutating func validate() throws {
        if let api {
            guard api.hasPrefix("3.0.") else {
                throw ValidationError("Only 3.0.x semantics are supported ('--api \(api)')")
            }
        }
        if localize {
            throw ValidationError(
                "Millstone resource localization is not supported by this port")
        }
        guard output == "mapnik" else {
            throw ValidationError("Only the 'mapnik' output format is supported ('--output \(output)')")
        }
    }

    mutating func run() throws {
        do {
            try runCompile()
        }
        catch let error as CLIError {
            FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
            throw ExitCode.failure
        }
    }

    private mutating func runCompile() throws {
        let clock: ContinuousClock = .init()
        let start = benchmark ? clock.now : nil

        let mmlURL: URL = .init(fileURLWithPath: projectFile)
        guard FileManager.default.fileExists(atPath: mmlURL.path) else {
            throw CLIError("The file '\(projectFile)' doesn't exist.")
        }

        let mmlData: String
        do {
            mmlData = try String(contentsOf: mmlURL, encoding: .utf8)
        }
        catch {
            throw CLIError("Failed to read '\(projectFile)': \(error.localizedDescription)")
        }

        let mml: MML
        do {
            mml = try MML(data: mmlData, basedir: mmlURL.deletingLastPathComponent())
        }
        catch {
            throw CLIError("\(error)")
        }

        var renderer = Renderer(ppi: ppi)
        guard let xml = renderer.render(mml) else {
            for message in renderer.messages where message.kind == .error {
                FileHandle.standardError.write(Data("\(message)\n".utf8))
            }
            throw ExitCode.failure
        }

        if !quiet {
            for message in renderer.messages where message.kind == .warning {
                FileHandle.standardError.write(Data("\(message)\n".utf8))
            }
        }

        if let outputFile {
            do {
                try xml.write(toFile: outputFile, atomically: true, encoding: .utf8)
            }
            catch {
                throw CLIError("Failed to write '\(outputFile)': \(error.localizedDescription)")
            }
        }
        else {
            print(xml)
        }

        if let start {
            let duration = clock.now - start
            let milliseconds = Double(duration.components.seconds) * 1000.0
                + Double(duration.components.attoseconds) / 1e15
            FileHandle.standardError.write(
                Data(String(format: "Total compile time: %.3fms\n", milliseconds).utf8))
        }
    }
}

// MARK: - Error types

/// An error type used to represent recoverable CLI operation failures.
struct CLIError: LocalizedError, CustomStringConvertible {
    /// A human-readable description of the error.
    let errorDescription: String

    /// The same text as `errorDescription`, so Foundation's error printing
    /// shows the message instead of the type's debug dump.
    var description: String {
        errorDescription
    }

    /// Creates a CLI error with the given description.
    /// - Parameter errorDescription: A description of the error.
    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
}
