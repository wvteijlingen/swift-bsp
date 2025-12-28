import ArgumentParser
import Foundation
import LanguageServerProtocolTransport
import Logging
import SwiftBuild

nonisolated(unsafe) var logger = Logger(label: "xcode-bsp")

@main
struct CLI: AsyncParsableCommand {
    @MainActor static var projectFileName: String!
    @Option var project: String

    @MainActor
    func run() async throws {
        let pwd = FileManager.default.currentDirectoryPath

        LoggingSystem.bootstrap { _ in
            FileLogHandler(fileURL: URL(filePath: "\(pwd)/.xcodebsp/output.log"))
        }

        Self.projectFileName = project

        logger.info("")
        logger.info("---------------------------")
        logger.info("Starting Xcode Build Server")
        logger.info("directory: \(pwd)")
        logger.info("project:   \(project)")
        logger.info("---------------------------")

        Task {
            BuildServer().start()
        }

        // Park the main function by sleeping for 10 years. All request handling is done on other threads and
        // sourcekit-lsp exits by calling `_Exit` when it receives a shutdown notification.
        while true {
            try? await Task.sleep(for: .seconds(60 * 60 * 24 * 365 * 10))
        }

        logger.info("Exiting!")
    }
}
