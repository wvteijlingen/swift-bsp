import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import SwiftBuild

@main
struct CLI: AsyncParsableCommand {
    @Option var project: String?
    @Option var logLevel: Logger.Level = .warning
    @Flag var persistLog = false

    @MainActor
    func run() async throws {
        let pwd = FileManager.default.currentDirectoryPath
        let logFileURL = URL(filePath: "\(pwd)/.xcode-bsp/xcode-bsp.log")

        if !persistLog {
            try? FileManager.default.removeItem(at: logFileURL)
        }

        let logger = Logger(fileURL: logFileURL, minLevel: logLevel)

        let projectFilePath = if let project {
            try AbsolutePath(validating: pwd).appending(component: project)
        } else {
            findXcodeProjectOrWorkspace(in: pwd)
        }

        guard let projectFilePath else {
            throw BuildServerError.cannotDetermineXcodeProject
        }

        logger.info("---------------------------")
        logger.info("Starting Xcode Build Server")
        logger.info("directory: \(pwd)")
        logger.info("project:   \(projectFilePath)")
        logger.info("---------------------------")

        Task {
            let buildServer = SwiftBSPMessageHandler(
                projectFilePath: projectFilePath,
                logger: logger,
                onExit: { @Sendable code in
                    let logLevel = code == 0 ? Logger.Level.info : Logger.Level.error
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

private func findXcodeProjectOrWorkspace(in directory: String) -> AbsolutePath? {
    let fileManager = FileManager.default

    guard let contents = try? fileManager.contentsOfDirectory(
        at: URL(filePath: directory),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let pathString = contents.first { url in
        let ext = url.pathExtension.lowercased()
        return ext == "xcworkspace" || ext == "xcodeproj"
    }?.path(percentEncoded: false)

    return pathString.flatMap { try? AbsolutePath(validating: $0) }
}
