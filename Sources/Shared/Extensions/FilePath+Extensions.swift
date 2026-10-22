import Foundation
import System
import BuildServerProtocol

extension FilePath {
    public var fileURI: URI {
        URI(filePath: self.string, isDirectory: false)
    }

    public var fileURL: URL {
        URL(filePath: self.string)
    }
}
