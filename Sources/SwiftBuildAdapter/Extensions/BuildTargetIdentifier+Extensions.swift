import BuildServerProtocol
import SwiftBuild
import Shared

private enum Key {
    static let targetGUIDKey = "targetGUID"
    static let configuredTargetGUIDKey = "configuredTargetGUID"
}

extension BuildTargetIdentifier {
    init(configuredTargetIdentifier: SWBConfiguredTargetIdentifier) throws {
        try self.init(
            kind: .swiftBuildConfiguredTarget,
            queryItems: [
                Key.targetGUIDKey: configuredTargetIdentifier.targetGUID.rawValue,
                Key.configuredTargetGUIDKey: configuredTargetIdentifier.rawGUID
            ]
        )
    }

    public var swiftBuildTarget: SWBConfiguredTargetIdentifier {
        get throws {
            let components = try components(forKind: .swiftBuildConfiguredTarget)

            guard let targetGUID = components.value(forFirstQueryItemWithName: Key.targetGUIDKey),
                  let configuredTargetGUID = components.value(forFirstQueryItemWithName: Key.configuredTargetGUIDKey)
            else {
                throw BuildServerError.invalidTargetIdentifier(uri.stringValue)
            }

            return SWBConfiguredTargetIdentifier(
                rawGUID: configuredTargetGUID,
                targetGUID: SWBTargetGUID(rawValue: targetGUID)
            )
        }
    }
}
