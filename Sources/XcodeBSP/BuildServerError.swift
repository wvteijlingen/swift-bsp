enum BuildServerError: Error {
    case projectNotInitialized
    case cannotLoadBuildDescriptionID
    case noWorkspaceInfo
}
