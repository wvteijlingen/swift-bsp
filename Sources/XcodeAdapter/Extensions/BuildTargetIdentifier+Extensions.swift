import BuildServerProtocol
import Foundation
import BuildServerProtocol
import XcodeProj
import Shared

private enum Key {
    static let name = "name"
}

extension BuildTargetIdentifier {
    init(xcodeScheme: XCScheme) throws {
        try self.init(
            kind: .xcodeScheme,
            queryItems: [Key.name: xcodeScheme.name]
        )
    }

    var xcodeTarget: XcodeTargetIdentifier {
        get throws {
            let components = try components(forKind: .xcodeScheme)

            guard let schemeName = components.value(forFirstQueryItemWithName: Key.name) else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            return XcodeTargetIdentifier(schemeName: schemeName)
        }
    }
}
