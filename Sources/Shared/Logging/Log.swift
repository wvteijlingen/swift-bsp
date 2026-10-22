import OSLog

public enum Log {
    public static let `default` = Logger(subsystem: "nl.wardvanteijlingen.swift-bsp", category: "swift-bsp")
    public static let buildSystem = Logger(subsystem: "nl.wardvanteijlingen.swift-bsp", category: "buildsystem")
}
