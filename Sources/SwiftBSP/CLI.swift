import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import OSLog
import SKLogging
import SwiftBuild
import System

@main
struct CLI: AsyncParsableCommand {
    func run() async throws {
        _ = Task {
            do {
                try await runServer()
            } catch {
                Log.default.error("Encountered error: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        // Park the main function by sleeping for 10 years
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
        }

        Log.default.info("Exiting")
    }

    private func runServer() async throws {
        LoggingScope.configureDefaultLoggingSubsystem("nl.wardvanteijlingen.swift-bsp")

        Log.default.info("Running in \(FileManager.default.currentDirectoryPath, privacy: .public)")

        let workingDirectory = FilePath(FileManager.default.currentDirectoryPath)
        let config = try makeConfiguration(workingDirectory: workingDirectory)

        if !FileManager.default.fileExists(atPath: config.scratchPath.string) {
            try FileManager.default.createDirectory(
                atPath: config.scratchPath.string, withIntermediateDirectories: true)
        }

        Log.default.info(
            "Starting in '\(workingDirectory, privacy: .public)' for '\(config.xcodeProjectPath, privacy: .public)'"
        )

        Log.default.info("Configuration: \(String(describing: config), privacy: .public)")

        let messageMirrorFile: FileHandle? =
            config.verboseLogging == true
            ? try messageMirrorHandle(scratchPath: config.scratchPath)
            : nil

        let server = try await SwiftBSPMessageHandler(
            config: config,
            messageMirrorFile: messageMirrorFile,
            onExit: { @Sendable code in
                Log.default.log(
                    level: code == 0 ? OSLogType.info : .error,
                    "Exiting with code \(code, privacy: .public)"
                )

                _Exit(code)
            }
        )

        await server.start()
    }
}

private func makeConfiguration(workingDirectory: FilePath) throws -> Configuration {
    let configFilePath = workingDirectory.appending("buildServer.json")
    let userDefinedConfiguration = try BuildServerJSON(jsonFilePath: configFilePath).swiftBSP

    let scratchPad =
        if let userDefinedScratchPad = userDefinedConfiguration?.scratchPath.map({ FilePath($0) }) {
            if userDefinedScratchPad.isAbsolute {
                userDefinedScratchPad
            } else {
                workingDirectory.appending(userDefinedScratchPad.string)
            }
        } else {
            workingDirectory.appending(".swift-bsp")
        }

    let containerPath =
        if let project = userDefinedConfiguration?.project {
            workingDirectory.appending(project)
        } else {
            findXcodeWorkspaceOrProject(in: workingDirectory)
        }

    guard let containerPath else { throw BuildServerError.cannotDetermineXcodeProject }

    return Configuration(
        configFilePath: configFilePath,
        verboseLogging: userDefinedConfiguration?.verboseLogging ?? false,
        xcodeProjectPath: containerPath,
        workspacePath: workingDirectory,
        scratchPath: scratchPad,
        configuration: userDefinedConfiguration?.configuration,
        runDestination: userDefinedConfiguration?.runDestination
    )
}

private func messageMirrorHandle(scratchPath: FilePath) throws -> FileHandle {
    let logsDirectory = scratchPath.appending("logs")
    let logURL = logsDirectory.appending("\(Date().timeIntervalSince1970).log").fileURL

    if !FileManager.default.fileExists(atPath: logsDirectory.string) {
        try FileManager.default.createDirectory(atPath: logsDirectory.string, withIntermediateDirectories: true)
    }

    try "".write(to: logURL, atomically: true, encoding: .utf8)

    Log.default.info("Logging messages to \(logURL.path(percentEncoded: false), privacy: .public)")

    return try FileHandle(forUpdating: logURL)
}

private func findXcodeWorkspaceOrProject(in directory: FilePath) -> FilePath? {
    let fileManager = FileManager.default

    guard
        let contents = try? fileManager.contentsOfDirectory(
            at: URL(filePath: directory.string),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    else {
        return nil
    }

    let xcworkspace = contents.first { url in
        url.pathExtension.lowercased() == "xcworkspace"
    }?.path(percentEncoded: false)

    let xcodeproj = contents.first { url in
        url.pathExtension.lowercased() == "xcodeproj"
    }?.path(percentEncoded: false)

    return (xcworkspace ?? xcodeproj).flatMap { FilePath($0) }
}

private struct BuildServerJSON: Decodable, Sendable {
    let swiftBSP: Configuration.UserDefined?

    init(jsonFilePath: FilePath) throws {
        do {
            Log.default.debug("Reading configuration from \(jsonFilePath, privacy: .public)")
            let data = try Data(contentsOf: URL(filePath: jsonFilePath.string))
            self = try JSONDecoder().decode(BuildServerJSON.self, from: data)
        } catch {
            throw BuildServerError.invalidConfig(error)
        }
    }
}
