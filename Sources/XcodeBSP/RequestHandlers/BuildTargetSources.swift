////
////  BuildTargetSources.swift
////  xcode-bsp
////
////  Created by Ward van Teijlingen on 16/11/2025.
////
//
//import LanguageServerProtocol
//import BuildServerProtocol
//
//struct BuildTargetSourcesRequestHandler: RequestHandler {
//    private let request: BuildTargetSourcesRequest
//
//    init(request: BuildTargetSourcesRequest) {
//        self.request = request
//    }
//
//    func handle(notify: Notify) async throws -> BuildTargetSourcesResponse {
//        let sourceItems = try await Session.current.xcodeProject.loadBuildSources(targetIdentifiers: request.targets)
//        return BuildTargetSourcesResponse(items: sourceItems)
//    }
//}
