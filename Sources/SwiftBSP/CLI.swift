import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import SwiftBuild
import OSLog

let logger = Logger(subsystem: "nl.wardvanteijlingen.swift-bsp", category: "")

@main
struct CLI: AsyncParsableCommand {
    func run() async throws {
        do {
            try await runThrowing()
        } catch {
            logger.error("Encountered error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func runThrowing() async throws {
        let workingDirectory = try AbsolutePath(validating: FileManager.default.currentDirectoryPath)
        let config = try BuildServerConfig(jsonFilePath: workingDirectory.appending(component: "buildServer.json"))
        let logFileURL = URL(filePath: "\(workingDirectory)/build/swift-bsp.log")

        try? FileManager.default.removeItem(at: logFileURL)

        let logger = FileLogger(
            fileURL: logFileURL,
            minLevel: .debug,
            enabled: config.swiftBSP?.verboseLogging == true
        )

        let projectFilePath = if let project = config.swiftBSP?.project {
            workingDirectory.appending(component: project)
        } else {
            findXcodeWorkspaceOrProject(in: workingDirectory)
        }

        guard let projectFilePath else {
            throw BuildServerError.cannotDetermineXcodeProject
        }

        logger.info( "---------------------------")
        logger.info( "Starting Xcode Build Server")
        logger.info( "directory: \(workingDirectory)")
        logger.debug("config:    \(config)")
        logger.info( "project:   \(projectFilePath)")
        logger.info( "---------------------------")

        Task {
            let buildServer = SwiftBSPMessageHandler(
                projectFilePath: projectFilePath,
                config: config,
                logger: logger,
                onExit: { @Sendable code in
                    let logLevel = code == 0 ? FileLogger.Level.info : FileLogger.Level.error
                    logger.log(logLevel, message: "Exiting with code \(code)")
                    _Exit(code)
                })

            await buildServer.start()
        }

        // Park the main function by sleeping for 10 years
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
        }

        logger.info("Exiting!")
    }
}

private func findXcodeWorkspaceOrProject(in directory: AbsolutePath) -> AbsolutePath? {
    let fileManager = FileManager.default

    guard let contents = try? fileManager.contentsOfDirectory(
        at: URL(filePath: directory.pathString),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let xcworkspace = contents.first { url in
        url.pathExtension.lowercased() == "xcworkspace"
    }?.path(percentEncoded: false)

    let xcodeproj = contents.first { url in
        url.pathExtension.lowercased() == "xcodeproj"
    }?.path(percentEncoded: false)

    return (xcworkspace ?? xcodeproj).flatMap { try? AbsolutePath(validating: $0) }
}
