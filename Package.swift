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
            name: "SwiftHTTPie",
            targets: ["SwiftHTTPie"]
        ),
        .executable(
            name: "swift-httpie",
            targets: ["SwiftHTTPieCLI"]
        ),
        .executable(
            name: "PeerDemo",
            targets: ["PeerDemo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.61.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0")
    ],
    targets: [
        .target(
            name: "SwiftHTTPie",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types")
            ]
        ),
        .executableTarget(
            name: "SwiftHTTPieCLI",
            dependencies: [
                "SwiftHTTPie"
            ]
        ),
        .executableTarget(
            name: "PeerDemo",
            dependencies: [
                "SwiftHTTPie",
                "SwiftHTTPieTestSupport",
            ],
            path: "Examples/PeerDemo"
        ),
        .testTarget(
            name: "SwiftHTTPieTests",
            dependencies: [
                "SwiftHTTPie",
                "SwiftHTTPieTestSupport"
            ],
            path: "Tests/SwiftHTTPieTests"
        ),
        .target(
            name: "SwiftHTTPieTestSupport",
            dependencies: [
                "SwiftHTTPie",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl")
            ],
            path: "Tests/TestSupport"
        ),
        .target(
            name: "SwiftHTTPieDocs",
            dependencies: ["SwiftHTTPie"],
            path: "Docs",
            resources: [
                .copy("SwiftHTTPie.docc")
            ]
        ),
    ]
)
