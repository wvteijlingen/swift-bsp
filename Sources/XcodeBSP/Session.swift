////
////  Session.swift
////  xcode-bsp
////
////  Created by Ward van Teijlingen on 16/11/2025.
////
//
//import Foundation
//import Path
//
//actor Session {
//    static var current: Session {
//        get throws {
//            if let _current { return _current }
//            throw BuildServerError.sessionNotStarted
//        }
//    }
//
//    nonisolated(unsafe) private static var _current: Session?
//
//    let projectRoot: AbsolutePath
//    let xcodeProject: XcodeProject
//
//    private init(root: AbsolutePath) async throws {
//        logger.info("Starting session at '\(root)'")
////        let configData = try Data(contentsOf: root.appendingPathComponent("buildServer.json"))
////        let config = try JSONDecoder().decode(Config.self, from: configData)
//
//        self.projectRoot = root
////        self.config = config
//        self.xcodeProject = try await XcodeProject(projectRoot: root, projectFileName: CLI.projectFileName)
//
//        logger.info("Started session at '\(root)'")
//    }
//
//    static func finish() {
//        _current = nil
//    }
//
//    static func start(projectRoot: AbsolutePath) async throws {
//        if _current != nil { throw BuildServerError.sessionAlreadyStarted }
//        _current = try await Session(root: projectRoot)
//    }
//}
