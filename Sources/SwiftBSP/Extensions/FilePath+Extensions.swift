import BuildServerProtocol
import Foundation
import System

extension FilePath {
    var fileURI: URI {
        URI(filePath: self.string, isDirectory: false)
    }

    var fileURL: URL {
        URL(filePath: self.string)
    }
}
