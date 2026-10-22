import BuildServerProtocol
import LanguageServerProtocol

public struct BuildTargetCompileRequest: BSPRequest, Hashable {
    public static let method: String = "buildTarget/compile"
    public typealias Response = BuildTargetCompileResponse

    public var targets: [BuildTargetIdentifier]
    public var destination: BuildTargetDestinationIdentifier?
    public var originId: OriginId?
    public var arguments: [String]?

    public init(
        targets: [BuildTargetIdentifier],
        destination: BuildTargetDestinationIdentifier? = nil,
        originId: OriginId? = nil,
        arguments: [String]? = nil
    ) {
        self.targets = targets
        self.destination = destination
        self.originId = originId
        self.arguments = arguments
    }
}

public struct BuildTargetCompileResponse: ResponseType, Hashable {
    public let statusCode: StatusCode;

    /// Kind of data to expect in the `data` field. If this field is not set, the kind of data is not specified.
    public var dataKind: BuildTargetCompileResponseDataKind?

    /// Language-specific metadata about this target.
    /// See ScalaBuildTarget as an example.
    public var data: LSPAny?

    public init(
        statusCode: StatusCode,
        dataKind: BuildTargetCompileResponseDataKind? = nil,
        data: LSPAny? = nil
    ) {
        self.statusCode = statusCode
        self.dataKind = dataKind
        self.data = data
    }
}

public struct BuildTargetCompileResponseDataKind: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let artifacts = BuildTargetCompileResponseDataKind(rawValue: "artifacts")
}
