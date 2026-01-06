import BuildServerProtocol
import SwiftBuild

enum BuildServerError: Error {
    case projectNotInitialized
    case cannotLoadBuildDescriptionID
    case noWorkspaceInfo
    case invalidFileURI(URI)
}

struct InvalidTargetIdentifierError: Swift.Error, CustomStringConvertible {
    let target: BuildTargetIdentifier

    var description: String {
        return "Invalid target identifier \(target)"
    }
}

struct FailedToConvertSwiftBuildTargetToUrlError: Swift.Error, CustomStringConvertible {
    var configuredTargetIdentifier: SWBConfiguredTargetIdentifier

    var description: String {
        return "Failed to generate URL for configured target '\(configuredTargetIdentifier.rawGUID)'"
    }
}
