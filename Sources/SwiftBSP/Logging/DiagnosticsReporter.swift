import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport

struct DiagnosticsReporter: Sendable {
    private let connection: (any Connection)?

    init(connection: (any Connection)?) {
        self.connection = connection
    }

    func report(
        _ diagnostics: [Diagnostic],
        textDocument: BuildServerProtocol.TextDocumentIdentifier,
        buildTarget: BuildTargetIdentifier,
        reset: Bool
    ) -> Void {
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
