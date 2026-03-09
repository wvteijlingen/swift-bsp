import BuildServerProtocol
import Foundation
import SwiftBuild

enum BuildServerError: Error, LocalizedError {
    case cannotDetermineXcodeProject
    case projectNotInitialized
    case buildServerNotStarted
    case projectAlreadyInitialized
    case cannotLoadBuildDescriptionID
    case noWorkspaceInfo
    case invalidFileURI(URI)
    case cannotCreateBuildTargetIdentifier(from: SWBConfiguredTargetIdentifier)
    case invalidTargetIdentifier(URL)
    case invalidConfig(Error)
    case invalidHomebrewPrefix

    var errorDescription: String? {
        switch self {
        case .cannotDetermineXcodeProject:
            "Cannot determine Xcode project or workspace. Provide the filename as an argument using '--project'"
        case .cannotCreateBuildTargetIdentifier(let from):
            "Cannot create build target identifier from '\(from)'"
        case .cannotLoadBuildDescriptionID:
            "Cannot load build description ID"
        case .invalidFileURI(let uri):
            "Invalid file URI: \(uri.arbitrarySchemeURL)"
        case .invalidTargetIdentifier(let identifier):
            "Invalid target identifier: \(identifier)"
        case .noWorkspaceInfo:
            "No workspace info available"
        case .projectNotInitialized:
            "Project not initialized"
        case .projectAlreadyInitialized:
            "Project already initialized"
        case .invalidConfig(let error):
            "Could not read configuration: \(error.localizedDescription)"
        case .buildServerNotStarted:
            "The build server was not started"
        case .invalidHomebrewPrefix:
            "Invalid Homebrew prefix"
        }
    }
}
