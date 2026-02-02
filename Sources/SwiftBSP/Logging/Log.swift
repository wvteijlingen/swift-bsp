import OSLog

enum Log {
    static let `default` = Logger(subsystem: "nl.wardvanteijlingen.swift-bsp", category: "swift-bsp")
    static let buildSystem = Logger(subsystem: "nl.wardvanteijlingen.swift-bsp", category: "buildsystem")
}
