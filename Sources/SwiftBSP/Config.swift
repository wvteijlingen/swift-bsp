import Foundation
import System

public struct Configuration: Decodable, Sendable {
    public let configFilePath: FilePath
    public let verboseLogging: Bool
    public let xcodeProjectPath: FilePath
    public let workspacePath: FilePath
    public var scratchPath: FilePath
    public let configuration: String?
    public let runDestination: RunDestination?

    public init(
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
    public struct UserDefined: Decodable, Sendable {
        public let verboseLogging: Bool?
        public let project: String?
        public let configuration: String?
        public let runDestination: RunDestination?
        public let scratchPath: String?
    }

    public struct RunDestination: Decodable, Sendable {
        public let platform: String?
        public let sdk: String
    }
}
