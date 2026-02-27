// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NWAsyncSocket",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "NWAsyncSocket",
            targets: ["NWAsyncSocket"]
        ),
        .executable(
            name: "SwiftDemo",
            targets: ["SwiftDemo"]
        ),
    ],
    targets: [
        .target(
            name: "NWAsyncSocket",
            path: "Sources/NWAsyncSocket"
        ),
        .executableTarget(
            name: "SwiftDemo",
            dependencies: ["NWAsyncSocket"],
            path: "Examples/SwiftDemo"
        ),
        .testTarget(
            name: "NWAsyncSocketTests",
            dependencies: ["NWAsyncSocket"],
            path: "Tests/NWAsyncSocketTests"
        ),
    ]
)
