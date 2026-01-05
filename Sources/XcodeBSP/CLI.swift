import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import Logging
import SwiftBuild

nonisolated(unsafe) var logger = Logger(label: "xcode-bsp")

@main
struct CLI: AsyncParsableCommand {
    @Option var project: String
    @Flag var persistLog = false

    @MainActor
    func run() async throws {
        let pwd = FileManager.default.currentDirectoryPath
        let projectFilePath = try AbsolutePath(validating: pwd).appending(component: project)
        let logFileURL = URL(filePath: "\(pwd)/.xcodebsp/xcodebsp.log")

        if !persistLog {
            try? FileManager.default.removeItem(at: logFileURL)
        }

        LoggingSystem.bootstrap { _ in
            FileLogHandler(fileURL: logFileURL)
        }

        logger.info("---------------------------")
        logger.info("Starting Xcode Build Server")
        logger.info("directory: \(pwd)")
        logger.info("project:   \(project)")
        logger.info("---------------------------")

        Task {
            let buildServer = BuildServer(
                projectFilePath: projectFilePath,
                onExit: { @Sendable code in
                    _Exit(code)
                })

            await buildServer.start()
        }

        // Park the main function by sleeping for 10 years. All request handling is done on other threads and
        // sourcekit-lsp exits by calling `_Exit` when it receives a shutdown notification.
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
        }

        logger.info("Exiting!")
    }
}
