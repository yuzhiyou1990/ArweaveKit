// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArweaveKit",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(
            name: "ArweaveKit",
            targets: ["ArweaveKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/lukereichold/JOSESwift.git", .upToNextMajor(from: "2.2.4")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "8.1.1"))
    ],
    targets: [
        .target(
            name: "ArweaveKit",
            dependencies: ["JOSESwift","PromiseKit"],
            path: "Sources"),
        .testTarget(
            name: "ArweaveTests",
            dependencies: ["ArweaveKit"],
            path: "Tests",
            resources: [.process("test-key.json")])
    ]
)
