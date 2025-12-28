////
////  WorkspaceBuildTargetsRequest.swift
////  xcode-bsp
////
////  Created by Ward van Teijlingen on 17/11/2025.
////
//
//import LanguageServerProtocol
//import BuildServerProtocol
//
//struct WorkSpaceBuildTargetsRequestHandler: RequestHandler {
//    private let request: WorkspaceBuildTargetsRequest
//
//    init(request: WorkspaceBuildTargetsRequest) {
//        self.request = request
//    }
//
//    func handle(notify: Notify) async throws -> WorkspaceBuildTargetsResponse {
////        let buildTargets = try Session.current.xcodeProject.schemes()
//        let buildTargets = try await Session.current.xcodeProject.loadBuildTargets()
//        return WorkspaceBuildTargetsResponse(targets: buildTargets)
//    }
//}
