// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftPie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftPie",
            targets: ["SwiftPie"]
        ),
        .executable(
            name: "spie",
            targets: ["SwiftPieCLI"]
        ),
        .executable(
            name: "PeerDemo",
            targets: ["PeerDemo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.61.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "SwiftPie",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Rainbow", package: "Rainbow")
            ]
        ),
        .executableTarget(
            name: "SwiftPieCLI",
            dependencies: [
                "SwiftPie"
            ]
        ),
        .executableTarget(
            name: "PeerDemo",
            dependencies: [
                "SwiftPie",
                "SwiftPieTestSupport",
            ],
            path: "Examples/PeerDemo"
        ),
        .testTarget(
            name: "SwiftPieTests",
            dependencies: [
                "SwiftPie",
                "SwiftPieTestSupport"
            ],
            path: "Tests/SwiftPieTests"
        ),
        .target(
            name: "SwiftPieTestSupport",
            dependencies: [
                "SwiftPie",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl")
            ],
            path: "Tests/TestSupport"
        ),
        .target(
            name: "SwiftPieDocs",
            dependencies: ["SwiftPie"],
            path: "Docs",
            resources: [
                .copy("SwiftPie.docc")
            ]
        ),
    ]
)
