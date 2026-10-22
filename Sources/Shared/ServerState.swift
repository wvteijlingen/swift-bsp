public enum ServerState: Sendable {
    case waitingForInitializeRequest
    case waitingForInitializedNotification
    case running
    case shutdown
}
