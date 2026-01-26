import SwiftBuild
import System

extension SWBArenaInfo {
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
