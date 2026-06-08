import BuildServerProtocol
import LanguageServerProtocol

struct BuildTargetCompileRequest: BSPRequest, Hashable {
    static let method: String = "buildTarget/compile"
    typealias Response = BuildTargetCompileResponse

    var targets: [BuildTargetIdentifier]
    var destination: BuildTargetDestinationIdentifier?
    var originId: OriginId?
    var arguments: [String]?

    init(
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

struct BuildTargetCompileResponse: ResponseType, Hashable {
    let statusCode: StatusCode;

    /// Kind of data to expect in the `data` field. If this field is not set, the kind of data is not specified.
    var dataKind: BuildTargetCompileResponseDataKind?

    /// Language-specific metadata about this target.
    /// See ScalaBuildTarget as an example.
    var data: LSPAny?

    init(
        statusCode: StatusCode,
        dataKind: BuildTargetCompileResponseDataKind? = nil,
        data: LSPAny? = nil
    ) {
        self.statusCode = statusCode
        self.dataKind = dataKind
        self.data = data
    }
}

struct BuildTargetCompileResponseDataKind: RawRepresentable, Codable, Hashable, Sendable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let productPaths = BuildTargetCompileResponseDataKind(rawValue: "productPaths")
}
