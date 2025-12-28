//
//  Arena.swift
//  xcode-bsp
//
//  Created by Ward van Teijlingen on 24/11/2025.
//

import Path
import SwiftBuild

//struct Arena {
//    let root: AbsolutePath
//    let cachePath: AbsolutePath
//    let inferiorProductsPath: AbsolutePath
//    let derivedDataPath: AbsolutePath
//    let buildProductsPath: AbsolutePath
//    let buildIntermediatesPath: AbsolutePath
//    let pchPath: AbsolutePath
//    let indexRegularBuildProductsPath: AbsolutePath
//    let indexRegularBuildIntermediatesPath: AbsolutePath
//    let indexPCHPath: AbsolutePath
//    let indexDataStoreFolderPath: AbsolutePath
//
//    init(root: AbsolutePath) {
//        self.root = root
//        self.cachePath = root.appending(component: "cache")
//        self.inferiorProductsPath = root.appending(component: "inferiorProducts")
//        self.derivedDataPath = root.appending(component: "derivedData")
//        self.buildProductsPath = root.appending(component: "buildProducts")
//        self.buildIntermediatesPath = root.appending(component: "buildIntermediates")
//        self.pchPath = root.appending(component: "pch")
//        self.indexRegularBuildProductsPath = root.appending(component: "indexRegularBuildProducts")
//        self.indexRegularBuildIntermediatesPath = root.appending(component: "indexRegularBuildIntermediates")
//        self.indexPCHPath = root.appending(component: "indexPCH")
//        self.indexDataStoreFolderPath = root.appending(component: "indexDataStoreFolder")
//    }
//}

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
