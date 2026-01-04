import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import Logging
import SwiftBuild

nonisolated(unsafe) var logger = Logger(label: "xcode-bsp")

@main
struct CLI: AsyncParsableCommand {
    @Option var project: String

    @MainActor
    func run() async throws {
        let pwd = FileManager.default.currentDirectoryPath
        let projectFilePath = try AbsolutePath(validating: pwd).appending(component: project)

        LoggingSystem.bootstrap { _ in
            FileLogHandler(fileURL: URL(filePath: "\(pwd)/.xcodebsp/output.log"))
        }

        logger.info("")
        logger.info("---------------------------")
        logger.info("Starting Xcode Build Server")
        logger.info("directory: \(pwd)")
        logger.info("project:   \(project)")
        logger.info("---------------------------")

        Task {
            let buildServer = BuildServer(projectFilePath: projectFilePath)
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
