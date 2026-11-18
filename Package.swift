// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Pinned to 6.2 — the LOWEST toolchain that must be able to build this
// package, set by the CI runner image (macos-15's newest Xcode, 26.3, ships
// Swift 6.2.4): every bump is immediately reverted by CI (6.4 → 6.3 for the
// macos-26 pool, 6.3 → 6.2 for macos-15). Nothing in the sources needs
// 6.3-only features; newer toolchains build tools-6.2 packages unchanged.

import PackageDescription

let package = Package(
    name: "BasicList",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BasicList",
            targets: ["BasicList"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BasicList",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),

        .testTarget(
            name: "BasicListTests",
            dependencies: [
                "BasicList"
            ],
        )

    ]
)
