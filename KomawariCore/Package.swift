// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KomawariCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KomawariCore", targets: ["KomawariCore"]),
    ],
    targets: [
        .target(name: "KomawariCore"),
        .testTarget(
            name: "KomawariCoreTests",
            dependencies: ["KomawariCore"],
            resources: [.copy("Golden")]
        ),
    ]
)
