////
////  RequestHandler.swift
////  xcode-bsp
////
////  Created by Ward van Teijlingen on 16/11/2025.
////
//
//import LanguageServerProtocol
//
//protocol RequestHandler {
//    typealias Notify = @Sendable (NotificationType) async throws -> Void
//    associatedtype Request: RequestType
//
//    init(request: Request)
//    func handle(notify: Notify) async throws -> Request.Response
//}
//
