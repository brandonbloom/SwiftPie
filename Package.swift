// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftHTTPie",
    platforms: [
        .macOS(.v13)
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
    targets: [
        .target(
            name: "SwiftHTTPieCore"
        ),
        .executableTarget(
            name: "SwiftHTTPieCLI",
            dependencies: [
                "SwiftHTTPieCore"
            ]
        ),
    ]
)
