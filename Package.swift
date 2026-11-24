// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LightCraftPicWatcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LightCraftPicWatcher", targets: ["LightCraftPicWatcher"]),
        // Exposed so the core can be built and tested on its own (`swift test`).
        .library(name: "WatcherCore", targets: ["WatcherCore"])
    ],
    // No third-party dependencies and no network code: photos never leave the Mac.
    targets: [
        // Everything without a UI: recognising images, the filters, the verified copy,
        // duplicates, the watch loop and reading LightCraft's settings.
        // Declarations use the `package` access level.
        .target(
            name: "WatcherCore",
            path: "Sources/WatcherCore"
        ),
        // The menu bar app (AppKit status item, SwiftUI views).
        .executableTarget(
            name: "LightCraftPicWatcher",
            dependencies: ["WatcherCore"],
            path: "Sources/LightCraftPicWatcher"
        ),
        .testTarget(
            name: "WatcherCoreTests",
            dependencies: ["WatcherCore"],
            path: "Tests/WatcherCoreTests"
        )
    ]
)
