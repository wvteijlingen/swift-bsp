import Foundation
import System
import BuildServerProtocol

extension FilePath {
  var fileURI: URI {
    URI(filePath: self.string, isDirectory: false)
  }
}