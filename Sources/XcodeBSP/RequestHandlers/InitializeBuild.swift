////
////  InitializeBuild.swift
////  xcode-bsp
////
////  Created by Ward van Teijlingen on 16/11/2025.
////
//
//import LanguageServerProtocol
//import BuildServerProtocol
//import Path
//
//struct InitializeBuildRequestHandler: RequestHandler {
//    let request: InitializeBuildRequest
//
//    init(request: InitializeBuildRequest) {
//        self.request = request
//    }
//
//    func handle(notify: Notify) async throws -> InitializeBuildResponse {
//        guard let fileURL = request.rootUri.fileURL else { fatalError() }
//        let rootPath = try AbsolutePath(validating: fileURL.path(percentEncoded: false))
//        try await Session.start(projectRoot: rootPath)
//
//        let xcodeProject = try Session.current.xcodeProject
//
//        Task {
//            do {
//                try await xcodeProject.buildSources(paths: <#T##[AbsolutePath]#>, target: <#T##String#>)
//            } catch {
//                logger.warning("Build failed: \(error)")
//            }
//        }
//
//        let languageIds = [Language.swift, .c, .cpp, .objective_c, .objective_cpp]
//
//        return await InitializeBuildResponse(
//            displayName: "xcode-bsp",
//            version: "0.0.1",
//            bspVersion: "2.2.0",
//            capabilities:
//                BuildServerCapabilities(
//                    compileProvider: CompileProvider(languageIds: languageIds),
//                    testProvider: TestProvider(languageIds: languageIds),
//                    runProvider: RunProvider(languageIds: languageIds),
//                    debugProvider: nil,
//                    inverseSourcesProvider: true,
//                    dependencySourcesProvider: true,
//                    resourcesProvider: true,
//                    outputPathsProvider: true,
//                    buildTargetChangedProvider: true,
//                    jvmRunEnvironmentProvider: true,
//                    jvmTestEnvironmentProvider: true,
//                    cargoFeaturesProvider: true,
//                    canReload: true,
//                    jvmCompileClasspathProvider: true
//                ),
//            dataKind: .sourceKit,
//            data: SourceKitInitializeBuildResponseData(
//                indexDatabasePath: xcodeProject.indexDatabasePath.pathString,
//                indexStorePath: xcodeProject.indexStorePath.pathString,
//                outputPathsProvider: false,
//                prepareProvider: false,
//                sourceKitOptionsProvider: true,
//                watchers: nil
//            ).encodeToLSPAny()
//        )
//    }
//}
