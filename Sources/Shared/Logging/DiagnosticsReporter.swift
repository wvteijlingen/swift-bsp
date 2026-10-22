import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport

public class DiagnosticsReporter: @unchecked Sendable {
    private let connection: (any Connection)?
    private var seenDocuments: Set<BuildServerProtocol.TextDocumentIdentifier> = []

    public init(connection: (any Connection)?) {
        self.connection = connection
    }

    public func clearAll(buildTarget: BuildTargetIdentifier) {
        for document in seenDocuments {
            let notification = PublishDiagnosticsNotification(
                textDocument: document,
                buildTarget: buildTarget, //fakeBuildTarget,
                originId: nil,
                diagnostics: [],
                reset: true
            )

            connection?.send(notification)
        }

        seenDocuments = []
    }

    public func report(
        _ diagnostics: [Diagnostic],
        textDocument: BuildServerProtocol.TextDocumentIdentifier,
        buildTarget: BuildTargetIdentifier,
        reset: Bool
    ) -> Void {
        seenDocuments.insert(textDocument)

        let notification = PublishDiagnosticsNotification(
            textDocument: textDocument,
            buildTarget: buildTarget,
            originId: nil,
            diagnostics: diagnostics,
            reset: reset
        )

        connection?.send(notification)
    }
}
