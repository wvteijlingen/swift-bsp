import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import System
import ToolsProtocolsSwiftExtensions

public protocol BSPAdapter: Sendable {
//    func handle(notification: some NotificationType) async throws -> (any NotificationType)?
//    func handle<Request>(requestAndReply: RequestAndReply<Request>) async

    // BSP Notifications
    func handleOnWatchedFilesDidChange(
        notification: OnWatchedFilesDidChangeNotification
    ) async throws -> OnBuildTargetDidChangeNotification?

    // BSP Requests
    func handleInitializeBuild(
        request: InitializeBuildRequest
    ) async throws -> (capabilities: BuildServerCapabilities, sourceKitData: LSPAny?)
    func handleBuildShutdown(request: BuildShutdownRequest) async throws -> VoidResponse
    func handleBuildTargetSources(request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse
    func handleWorkspaceBuildTargets(
        request: WorkspaceBuildTargetsRequest
    ) async throws -> WorkspaceBuildTargetsResponse
    func handleWorkspaceWaitForBuildSystemUpdates(
        request: WorkspaceWaitForBuildSystemUpdatesRequest
    ) async throws -> VoidResponse
    func handleBuildTargetCompile(
        request: BuildTargetCompileRequest
    ) async throws -> BuildTargetCompileResponse
    func handleBuildTargetRun(
        request: BuildTargetRunRequest
    ) async throws -> BuildTargetRunResponse

    // Destination Extension Requests
    func handleBuildTargetDestinations(
        request: BuildTargetDestinationsRequest
    ) async throws -> BuildTargetDestinationsResponse

    // SourceKit Extension Requests
    func handleBuildTargetPrepare(request: BuildTargetPrepareRequest) async throws -> VoidResponse
    func handleTextDocumentSourceKitOptions(request: TextDocumentSourceKitOptionsRequest) async throws -> TextDocumentSourceKitOptionsResponse
}