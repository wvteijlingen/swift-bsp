//
//  Config.swift
//  swift-bsp
//
//  Created by Ward van Teijlingen on 19/01/2026.
//

import Foundation
import System

struct BuildServerConfig: Decodable {
    let swiftBSP: SwiftBSP?

    init(jsonFilePath: FilePath) throws {
        do {
            logger.info("Reading configuration from \(jsonFilePath, privacy: .public)")
            let data = try Data(contentsOf: URL(filePath: jsonFilePath.string))
            self = try JSONDecoder().decode(BuildServerConfig.self, from: data)
        } catch {
            throw BuildServerError.invalidConfig(error)
        }
    }
}

extension BuildServerConfig {
    struct SwiftBSP: Decodable {
        let verboseLogging: Bool
        let project: String?
        let configuration: String?
        let runDestination: RunDestination?
    }

    struct RunDestination: Decodable {
        let platform: String?
        let sdk: String
    }
}
