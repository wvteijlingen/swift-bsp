import Path
import SwiftBuild

extension SWBArenaInfo {
    init(root: AbsolutePath, indexEnableDataStore: Bool) {
        self.init(
            derivedDataPath: root.appending(component: "derivedData").pathString,
            buildProductsPath: root.appending(component: "buildProducts").pathString,
            buildIntermediatesPath: root.appending(component: "buildIntermediates").pathString,
            pchPath: root.appending(component: "pch").pathString,
            indexRegularBuildProductsPath: root.appending(component: "indexRegularBuildProducts").pathString,
            indexRegularBuildIntermediatesPath: root.appending(component: "indexRegularBuildIntermediates").pathString,
            indexPCHPath: root.appending(component: "indexPCH").pathString,
            indexDataStoreFolderPath: root.appending(component: "indexDataStore").pathString,
            indexEnableDataStore: indexEnableDataStore
        )
    }
}
