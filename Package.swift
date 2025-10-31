// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftHTTPie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftHTTPieCore",
            targets: ["SwiftHTTPieCore"]
        ),
        .executable(
            name: "SwiftHTTPie",
            targets: ["SwiftHTTPieCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SwiftHTTPieCore",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types")
            ]
        ),
        .executableTarget(
            name: "SwiftHTTPieCLI",
            dependencies: [
                "SwiftHTTPieCore"
            ]
        ),
        .testTarget(
            name: "SwiftHTTPieCoreTests",
            dependencies: [
                "SwiftHTTPieCore"
            ]
        ),
    ]
)
