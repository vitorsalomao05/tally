import SwiftUI

/// Houdini for iPhone — app entry point. Reuses the shared `FetcherCore` (cookie
/// path) for all data; the UI here is a thin SwiftUI frontend (ADR-008).
///
/// TODO(xcode): this target only compiles in Xcode (iOS SDK). `swift build` on
/// CommandLineTools cannot build an iOS app. See `apps/ios/README.md`.
@main
struct HoudiniMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
