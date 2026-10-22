import BuildServerProtocol
import LanguageServerProtocol

public struct BuildTargetDestinationsRequest: BSPRequest, Hashable {
    public static let method: String = "buildTarget/destinations"
    public typealias Response = BuildTargetDestinationsResponse

    public var target: BuildTargetIdentifier
    public var originId: OriginId?

    public init(target: BuildTargetIdentifier, originId: OriginId? = nil) {
        self.target = target
        self.originId = originId
    }
}

public struct BuildTargetDestinationsResponse: ResponseType, Hashable {
    /// Name of the server
    public var destinations: [BuildTargetDestination]

    public init(
        destinations: [BuildTargetDestination]
    ) {
        self.destinations = destinations
    }
}

public struct BuildTargetDestination: Codable, Hashable, Sendable {
    public var displayName: String
    public var id: BuildTargetDestinationIdentifier

    public init(id: BuildTargetDestinationIdentifier, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct BuildTargetDestinationIdentifier: Codable, Hashable, Sendable {
    public var uri: URI

    public init(uri: URI) {
        self.uri = uri
    }
}

