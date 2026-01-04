//
//  BuildServerError.swift
//  xcode-bsp
//
//  Created by Ward van Teijlingen on 17/11/2025.
//

enum BuildServerError: Error {
    //    case sessionNotStarted
    //    case sessionAlreadyStarted
    case noTargetsFound
    case schemeNotFound
    case projectNotInitialized
    case unknown
    case cannotLoadBuildDescriptionID
}
