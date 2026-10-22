import BuildServerProtocol
import Foundation

private enum Key {
    static let scheme = "swift-bsp"
}

extension BuildTargetIdentifier {
    public enum Kind: String {
        case swiftBuildConfiguredTarget
        case xcodeScheme
    }

    public init(kind: Kind, queryItems: [String: String]) throws {
        let components = URLComponents(scheme: Key.scheme, host: kind.rawValue, queryItems: queryItems)

        guard let url = components.url else {
            throw BuildServerError.generic(
                "Cannot create BuildTargetIdentifier '\(kind)' from \(components)"
            )
        }

        self.init(uri: URI(url))
    }

    public var kind: Kind {
        get throws {
            guard let host = try validatedComponents.host, let kind = Kind(rawValue: host) else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            return kind
        }
    }

    public func components(forKind kind: Kind) throws -> URLComponents {
        let components = try validatedComponents

        guard components.host == kind.rawValue else {
            throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
        }

        return components
    }

    private var validatedComponents: URLComponents {
        get throws {
            guard let components = URLComponents(url: uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            guard components.scheme == Key.scheme else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            return components
        }
    }
}
