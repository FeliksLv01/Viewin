// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ViewinCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ViewinSnapshot", targets: ["ViewinSnapshot"]),
        .library(name: "ViewinConnection", targets: ["ViewinConnection"]),
        .library(name: "ViewinWorkspace", targets: ["ViewinWorkspace"]),
        .executable(name: "viewin", targets: ["ViewinCapture"]),
    ],
    dependencies: [
        .package(path: "../../ViewinSDK"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .executableTarget(name: "ViewinCapture", dependencies: ["ViewinConnection", "ViewinSnapshot"]),
        .target(name: "ViewinConnection", dependencies: [.product(name: "ViewinTransport", package: "ViewinSDK"), "ViewinSnapshot", .product(name: "ViewinProtocol", package: "ViewinSDK")]),
        .target(name: "ViewinWorkspace", dependencies: ["ViewinConnection", "ViewinSnapshot", .product(name: "ViewinProtocol", package: "ViewinSDK")]),
        .testTarget(name: "ViewinWorkspaceTests", dependencies: ["ViewinWorkspace", "ViewinTestSupport"]),
        .target(name: "ViewinTestSupport", dependencies: ["ViewinSnapshot"], path: "Tests/ViewinTestSupport", resources: [.copy("Fixtures")]),
        .target(name: "ViewinSnapshot", dependencies: [.product(name: "ViewinProtocol", package: "ViewinSDK"), .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        .testTarget(name: "ViewinConnectionTests", dependencies: ["ViewinConnection", .product(name: "ViewinTransport", package: "ViewinSDK"), .product(name: "ViewinProtocol", package: "ViewinSDK")]),
        .testTarget(name: "ViewinSnapshotTests", dependencies: ["ViewinSnapshot", "ViewinTestSupport", .product(name: "ViewinProtocol", package: "ViewinSDK"), .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
    ]
)
