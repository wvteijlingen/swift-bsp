import BuildServerProtocol
import LanguageServerProtocol

struct BuildTargetDestinationsRequest: BSPRequest, Hashable {
    static let method: String = "buildTarget/destinations"
    typealias Response = BuildTargetDestinationsResponse

    var target: BuildTargetIdentifier
    var originId: OriginId?

    init(target: BuildTargetIdentifier, originId: OriginId? = nil) {
        self.target = target
        self.originId = originId
    }
}

struct BuildTargetDestinationsResponse: ResponseType, Hashable {
    /// Name of the server
    var destinations: [BuildTargetDestination]

    init(
        destinations: [BuildTargetDestination]
    ) {
        self.destinations = destinations
    }
}

struct BuildTargetDestination: Codable, Hashable, Sendable {
    var displayName: String
    var id: BuildTargetDestinationIdentifier

    init(id: BuildTargetDestinationIdentifier, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

struct BuildTargetDestinationIdentifier: Codable, Hashable, Sendable {
    var uri: URI

    init(uri: URI) {
        self.uri = uri
    }
}

extension BuildTargetDestinationIdentifier {
    init(xcodeDestination: XcodeDestination) throws {
        self.uri = try URI(string: "swift-bsp://xcdestination?id=\(xcodeDestination.id)")
    }

    var id: String {
        // TODO: Use URLComponents
        uri.stringValue.replacingOccurrences(of: "swift-bsp://xcdestination?id=", with: "")
    }
}
