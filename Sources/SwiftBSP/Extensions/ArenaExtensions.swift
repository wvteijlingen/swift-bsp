import Path
import SwiftBuild

extension SWBArenaInfo {
    init(root: AbsolutePath, indexEnableDataStore: Bool) {
        self.init(
            derivedDataPath: root.pathString,
            buildProductsPath: root.appending(components: ["Build", "Products"]).pathString,
            buildIntermediatesPath: root.appending(components: ["Build", "Intermediates.noindex"]).pathString,
            pchPath: root.appending(component: "pch").pathString,
            indexRegularBuildProductsPath: root.appending(component: "indexRegularBuildProducts").pathString,
            indexRegularBuildIntermediatesPath: root.appending(component: "indexRegularBuildIntermediates").pathString,
            indexPCHPath: root.appending(component: "indexPCH").pathString,
            indexDataStoreFolderPath: root.appending(components: ["Index.noindex", "DataStore"]).pathString,
            indexEnableDataStore: indexEnableDataStore
        )
    }
}
