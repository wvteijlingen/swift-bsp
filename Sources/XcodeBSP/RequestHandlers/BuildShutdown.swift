////
////  BuildShutdown.swift
////  xcode-bsp
////
////  Created by Ward van Teijlingen on 16/11/2025.
////
//
//import LanguageServerProtocol
//import BuildServerProtocol
//
//struct BuildShutdownRequestHandler: RequestHandler {
//    private let request: BuildShutdownRequest
//
//    init(request: BuildShutdownRequest) {
//        self.request = request
//    }
//
//    func handle(notify: Notify) async throws -> VoidResponse {
//        Session.finish()
//
//        return VoidResponse()
//    }
//}
