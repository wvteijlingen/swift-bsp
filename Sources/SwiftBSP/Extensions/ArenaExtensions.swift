import SwiftBuild
import System

extension SWBArenaInfo {
    /// Creates an `SWBArenaInfo` instance with paths derived from the given root path.
    ///
    /// The arena paths mirror those used by Xcode. This enables users to re-use the same directory
    /// for swift-bsp and Xcodes DerivedData, which can help with caching and performance.
    init(root: FilePath, indexEnableDataStore: Bool) {
        self.init(
            derivedDataPath: root.string,
            buildProductsPath: root.appending(["Build", "Products"]).string,
            buildIntermediatesPath: root.appending(["Build", "Intermediates.noindex"]).string,
            pchPath: root.appending("pch").string,
            indexRegularBuildProductsPath: root.appending("indexRegularBuildProducts").string,
            indexRegularBuildIntermediatesPath: root.appending("indexRegularBuildIntermediates").string,
            indexPCHPath: root.appending("indexPCH").string,
            indexDataStoreFolderPath: root.appending(["Index.noindex", "DataStore"]).string,
            indexEnableDataStore: indexEnableDataStore
        )
    }
}
