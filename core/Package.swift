// swift-tools-version: 6.0
import PackageDescription
import Foundation

// FetcherCore — the shared, UI-less data layer for Tally (see ../ARCHITECTURE.md).
// `tally-cli` is the thin executable used to validate providers against a real
// account before any UI exists (see ../ROADMAP.md, Phase 1).

// Tests use swift-testing (`import Testing`). This machine has CommandLineTools
// only, which ships `Testing.framework` but doesn't put it on the default search
// path — so when that framework is present we add it explicitly. On a full-Xcode
// toolchain the path doesn't exist (and testing resolves natively), so no flags.
// Testing.framework loads @rpath/Testing.framework (in .../Developer/Frameworks)
// which in turn loads @rpath/lib_TestingInterop.dylib (in .../Developer/usr/lib).
// Both directories must be on the framework search path + runtime rpath.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltDeveloperLib = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let needsTestingFrameworkPath = FileManager.default.fileExists(
    atPath: cltFrameworks + "/Testing.framework"
)
let testSwiftSettings: [SwiftSetting] = needsTestingFrameworkPath
    ? [.unsafeFlags(["-F", cltFrameworks])] : []
let testLinkerSettings: [LinkerSetting] = needsTestingFrameworkPath
    ? [.unsafeFlags([
        "-F", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", cltDeveloperLib,
      ])] : []

let package = Package(
    name: "FetcherCore",
    platforms: [
        .macOS(.v14) // macOS 14+ / Apple Silicon only (README scope).
    ],
    products: [
        .library(name: "FetcherCore", targets: ["FetcherCore"]),
        .executable(name: "tally-cli", targets: ["tally-cli"]),
        .executable(name: "tally-selftest", targets: ["tally-selftest"]),
    ],
    targets: [
        .target(name: "FetcherCore"),
        .executableTarget(
            name: "tally-cli",
            dependencies: ["FetcherCore"]
        ),
        // Runnable mirror of FetcherCoreTests for CommandLineTools-only machines,
        // where `swift test`'s swift-testing runner no-ops (see target source).
        .executableTarget(
            name: "tally-selftest",
            dependencies: ["FetcherCore"]
        ),
        .testTarget(
            name: "FetcherCoreTests",
            dependencies: ["FetcherCore"],
            // JSON fixtures (OAuth + cookie usage dialects, org lists) read via
            // Bundle.module. `.copy` keeps the `Fixtures/` subdirectory intact.
            resources: [.copy("Fixtures")],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
)
