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
    ],
    targets: [
        .target(
            name: "NWAsyncSocket",
            path: "Sources/NWAsyncSocket"
        ),
        .testTarget(
            name: "NWAsyncSocketTests",
            dependencies: ["NWAsyncSocket"],
            path: "Tests/NWAsyncSocketTests"
        ),
    ]
)
