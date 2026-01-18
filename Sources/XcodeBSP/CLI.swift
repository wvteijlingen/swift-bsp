import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import SwiftBuild

@main
struct CLI: AsyncParsableCommand {
    @Option var project: String
    @Flag var persistLog = false
    @Option var logLevel: Logger.Level = .warning

    @MainActor
    func run() async throws {
        let pwd = FileManager.default.currentDirectoryPath
        let projectFilePath = try AbsolutePath(validating: pwd).appending(component: project)
        let logFileURL = URL(filePath: "\(pwd)/.xcode-bsp/xcode-bsp.log")

        if !persistLog {
            try? FileManager.default.removeItem(at: logFileURL)
        }

        let logger = Logger(fileURL: logFileURL, minLevel: logLevel)

        logger.info("---------------------------")
        logger.info("Starting Xcode Build Server")
        logger.info("directory: \(pwd)")
        logger.info("project:   \(project)")
        logger.info("---------------------------")

        Task {
            let buildServer = BuildServer(
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
