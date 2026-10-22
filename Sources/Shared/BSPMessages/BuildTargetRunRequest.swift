import BuildServerProtocol
import LanguageServerProtocol

public struct BuildTargetRunRequest: BSPRequest, Hashable {
    public static let method: String = "buildTarget/run"
    public typealias Response = BuildTargetRunResponse

    public var target: BuildTargetIdentifier
    public var destination: BuildTargetDestinationIdentifier?
    public var originId: OriginId?
    public var arguments: [String]?

    public init(
        target: BuildTargetIdentifier,
        destination: BuildTargetDestinationIdentifier? = nil,
        originId: OriginId? = nil,
        arguments: [String]? = nil
    ) {
        self.target = target
        self.destination = destination
        self.originId = originId
        self.arguments = arguments
    }
}

public struct BuildTargetRunResponse: ResponseType, Hashable {
    public let statusCode: StatusCode;
    public var originId: OriginId?

    public init(
        statusCode: StatusCode,
        originId: OriginId? = nil,
    ) {
        self.statusCode = statusCode
        self.originId = originId
    }
}