// swift-tools-version: 6.0
import PackageDescription

// Houdini — menu bar app (flagship surface). Built as a SwiftPM executable because
// this machine has only CommandLineTools (no full Xcode for xcodebuild/.xcodeproj).
// `build.sh` wraps the product into a proper .app bundle (LSUIElement + entitlements
// + ad-hoc hardened-runtime signing). Depends on the local FetcherCore by path.
let package = Package(
    name: "Houdini",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../core")
    ],
    targets: [
        // Target is "HoudiniApp" (not "Houdini") deliberately: the core package
        // ships a CLI executable target named `houdini`, and SwiftPM keys each
        // target's build tree off `<TargetName>.build/`. On a case-insensitive
        // APFS volume `Houdini.build/` and `houdini.build/` are the SAME folder,
        // so the two collide and the app's object files never get emitted. A
        // case-distinct target name avoids that. The shipped bundle binary is
        // still `Houdini` — build.sh copies $BINDIR/HoudiniApp → MacOS/Houdini.
        .executableTarget(
            name: "HoudiniApp",
            dependencies: [
                .product(name: "FetcherCore", package: "core")
            ],
            path: "Sources/Houdini",
            // App/AppKit glue doesn't need Swift 6 strict-concurrency checking;
            // FetcherCore itself stays in the default (Swift 6) mode.
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
