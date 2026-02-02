import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import OSLog
import SwiftBuild
import System

@main
struct CLI: AsyncParsableCommand {
    func run() async throws {
        do {
            try await runThrowing()
        } catch {
            Log.default.error("Encountered error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func runThrowing() async throws {
        let workingDirectory = FilePath(FileManager.default.currentDirectoryPath)
        let config = try BuildServerConfig(jsonFilePath: workingDirectory.appending("buildServer.json"))

        let projectFilePath = if let project = config.swiftBSP?.project {
            workingDirectory.appending(project)
        } else {
            findXcodeWorkspaceOrProject(in: workingDirectory)
        }

        guard let projectFilePath else {
            throw BuildServerError.cannotDetermineXcodeProject
        }

        Log.default.info("Starting in '\(workingDirectory, privacy: .public)' for '\(projectFilePath, privacy: .public)'")

        let messageMirrorFile: FileHandle?
        if config.swiftBSP?.verboseLogging == true {
            let fileURL = URL(filePath: "\(workingDirectory)/build/swift-bsp.log")
            Log.default.info("Logging messages to \(fileURL.path(percentEncoded: false), privacy: .public)")

            try? FileManager.default.removeItem(at: fileURL)
            try "".write(to: fileURL, atomically: true, encoding: .utf8)

            messageMirrorFile = try FileHandle(forUpdating: fileURL)
        } else {
            messageMirrorFile = nil
        }


        Task {
            let buildServer = SwiftBSPMessageHandler(
                projectFilePath: projectFilePath,
                config: config,
                messageMirrorFile: messageMirrorFile,
                onExit: { @Sendable code in
                    let logLevel = code == 0 ? OSLogType.info : .error
                    Log.default.log(level: logLevel, "Exiting with code \(code, privacy: .public)")
                    _Exit(code)
                })

            await buildServer.start()
        }

        // Park the main function by sleeping for 10 years
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
        }

        Log.default.info("Exiting")
    }
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
