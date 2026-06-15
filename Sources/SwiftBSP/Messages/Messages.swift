import LanguageServerProtocol
import BuildServerProtocol

private let defaultRequestTypes: [_RequestType.Type] = [
  BuildShutdownRequest.self,
  BuildTargetPrepareRequest.self,
  BuildTargetSourcesRequest.self,
  CreateWorkDoneProgressRequest.self,
  InitializeBuildRequest.self,
  RegisterForChanges.self,
  TextDocumentSourceKitOptionsRequest.self,
  WorkspaceBuildTargetsRequest.self,
  WorkspaceWaitForBuildSystemUpdatesRequest.self,
]

private let defaultNotificationTypes: [NotificationType.Type] = [
  CancelRequestNotification.self,
  FileOptionsChangedNotification.self,
  OnBuildExitNotification.self,
  OnBuildInitializedNotification.self,
  OnBuildLogMessageNotification.self,
  OnBuildTargetDidChangeNotification.self,
  OnWatchedFilesDidChangeNotification.self,
  TaskFinishNotification.self,
  TaskProgressNotification.self,
  TaskStartNotification.self,
]

private let extendedRequestTypes: [_RequestType.Type] = [
    BuildTargetDestinationsRequest.self,
    BuildTargetCompileRequest.self
]

private let extendedNotificationTypes: [NotificationType.Type] = [
    PublishDiagnosticsNotification.self
]

extension MessageRegistry {
    static let bspProtocolExtended = MessageRegistry(
        requests: defaultRequestTypes + extendedRequestTypes,
        notifications: defaultNotificationTypes + extendedNotificationTypes
    )
}
