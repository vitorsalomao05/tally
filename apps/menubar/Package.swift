// swift-tools-version: 6.0
import PackageDescription

// Tally — menu bar app (flagship surface). Built as a SwiftPM executable because
// this machine has only CommandLineTools (no full Xcode for xcodebuild/.xcodeproj).
// `build.sh` wraps the product into a proper .app bundle (LSUIElement + entitlements
// + ad-hoc hardened-runtime signing). Depends on the local FetcherCore by path.
let package = Package(
    name: "Tally",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../core")
    ],
    targets: [
        .executableTarget(
            name: "Tally",
            dependencies: [
                .product(name: "FetcherCore", package: "core")
            ],
            // App/AppKit glue doesn't need Swift 6 strict-concurrency checking;
            // FetcherCore itself stays in the default (Swift 6) mode.
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
