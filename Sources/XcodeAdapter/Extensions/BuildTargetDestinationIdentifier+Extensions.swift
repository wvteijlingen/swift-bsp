import Shared
import Foundation
import BuildServerProtocol

private enum Key {
    static let id = "id"
}

extension BuildTargetDestinationIdentifier {
    init(xcodeDestination: XcodeDestination) throws {
        let components = URLComponents(
            scheme: "swift-bsp",
            host: "xcdestination",
            queryItems: [Key.id: xcodeDestination.id]
        )

        guard let url = components.url else {
            throw BuildServerError.generic(
                "Cannot create BuildTargetDestinationIdentifier from \(components)"
            )
        }

        self.init(uri: URI(url))
    }

    var id: String {
        get throws {
            guard let components = URLComponents(url: uri.arbitrarySchemeURL, resolvingAgainstBaseURL: false) else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            guard let destinationID = components.value(forFirstQueryItemWithName: Key.id) else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            return destinationID
        }
    }
}
