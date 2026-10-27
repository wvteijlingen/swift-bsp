import Foundation
import System

struct Configuration: Decodable, Sendable {
    let configFilePath: FilePath
    let verboseLogging: Bool
    let xcodeProjectPath: FilePath
    let workspacePath: FilePath
    var scratchPath: FilePath
    let configuration: String?
    let runDestination: RunDestination?

    init(
        configFilePath: FilePath,
        verboseLogging: Bool,
        xcodeProjectPath: FilePath,
        workspacePath: FilePath,
        scratchPath: FilePath,
        configuration: String?,
        runDestination: Configuration.RunDestination?
    ) {
        self.configFilePath = configFilePath
        self.verboseLogging = verboseLogging
        self.xcodeProjectPath = xcodeProjectPath
        self.workspacePath = workspacePath
        self.scratchPath = scratchPath
        self.configuration = configuration
        self.runDestination = runDestination
    }
}

extension Configuration {
    struct UserDefined: Decodable, Sendable {
        let verboseLogging: Bool?
        let project: String?
        let configuration: String?
        let runDestination: RunDestination?
        let scratchPath: String?
    }

    struct RunDestination: Decodable, Sendable {
        let platform: String?
        let sdk: String
    }
}
