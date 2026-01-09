import BuildServerProtocol
import Foundation
import SwiftBuild

enum BuildServerError: Error {
    case projectNotInitialized
    case cannotLoadBuildDescriptionID
    case noWorkspaceInfo
    case invalidFileURI(URI)
    case cannotCreateBuiltTargetIdentifier(from: SWBConfiguredTargetIdentifier)
    case invalidTargetIdentifier(URL)
}
