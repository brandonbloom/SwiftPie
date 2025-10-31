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
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.61.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0")
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
                "SwiftHTTPieCore",
                "SwiftHTTPieTestSupport"
            ]
        ),
        .target(
            name: "SwiftHTTPieTestSupport",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl")
            ],
            path: "Tests/TestSupport"
        ),
    ]
)
