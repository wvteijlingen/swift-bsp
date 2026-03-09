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
        Task {
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

        #if Homebrew
            Log.default.info("Running in Homebrew environment")
        #endif

        let workingDirectory = FilePath(FileManager.default.currentDirectoryPath)
        let arenaPath = workingDirectory.appending("build")
        let config = try BuildServerConfig(jsonFilePath: workingDirectory.appending("buildServer.json"))

        let containerPath =
            if let project = config.swiftBSP?.project {
                workingDirectory.appending(project)
            } else {
                findXcodeWorkspaceOrProject(in: workingDirectory)
            }

        guard let containerPath else { throw BuildServerError.cannotDetermineXcodeProject }

        if !FileManager.default.fileExists(atPath: arenaPath.string) {
            try FileManager.default.createDirectory(atPath: arenaPath.string, withIntermediateDirectories: true)
        }

        Log.default.info("Starting in '\(workingDirectory, privacy: .public)' for '\(containerPath, privacy: .public)'")
        Log.default.info("Configuration: \(String(describing: config.swiftBSP), privacy: .public)")

        let messageMirrorFile: FileHandle? =
            config.swiftBSP?.verboseLogging == true
            ? try messageMirrorHandle(workingDirectory: workingDirectory)
            : nil

        let buildServer = try await SwiftBSPMessageHandler(
            containerPath: containerPath,
            arenaPath: arenaPath,
            config: config,
            messageMirrorFile: messageMirrorFile,
            onExit: { @Sendable code in
                Log.default.log(
                    level: code == 0 ? OSLogType.info : .error,
                    "Exiting with code \(code, privacy: .public)"
                )

                _Exit(code)
            })

        await buildServer.start()
    }
}

private func messageMirrorHandle(workingDirectory: FilePath) throws -> FileHandle {
    let fileURL = URL(filePath: "\(workingDirectory)/build/swift-bsp.log")

    try? FileManager.default.removeItem(at: fileURL)
    try "".write(to: fileURL, atomically: true, encoding: .utf8)

    Log.default.info("Logging messages to \(fileURL.path(percentEncoded: false), privacy: .public)")

    return try FileHandle(forUpdating: fileURL)
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
