// swift-tools-version: 6.0
import PackageDescription

// FetcherCore — the shared, UI-less data layer for Tally (see ../ARCHITECTURE.md).
// `tally-cli` is the thin executable used to validate providers against a real
// account before any UI exists (see ../ROADMAP.md, Phase 1).
let package = Package(
    name: "FetcherCore",
    platforms: [
        .macOS(.v14) // macOS 14+ / Apple Silicon only (README scope).
    ],
    products: [
        .library(name: "FetcherCore", targets: ["FetcherCore"]),
        .executable(name: "tally-cli", targets: ["tally-cli"]),
    ],
    targets: [
        .target(name: "FetcherCore"),
        .executableTarget(
            name: "tally-cli",
            dependencies: ["FetcherCore"]
        ),
    ]
)
