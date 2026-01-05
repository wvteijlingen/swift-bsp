enum BuildServerError: Error {
    case noTargetsFound
    case schemeNotFound
    case projectNotInitialized
    case cannotLoadBuildDescriptionID
    case noWorkspaceInfo
}
