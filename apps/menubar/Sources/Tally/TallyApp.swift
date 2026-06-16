import SwiftUI
import AppKit
import FetcherCore

/// Owns the app-scoped `UsageModel` and starts its 60s timer at launch.
///
/// The refresh timer lives HERE (app/model scope), never inside the menu/popover
/// view — a timer hosted inside the MenuBarExtra content stalls (known macOS bug,
/// see ARCHITECTURE.md "Menu bar app"). This is the only surface that hits a true
/// 60s cadence (ADR-002).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app — no Dock icon. Also set via LSUIElement in Info.plist; this
        // covers running the bare binary outside the bundle.
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }
}

struct TallyMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(model: appDelegate.model)
        } label: {
            MenuBarLabelContent(model: appDelegate.model)
        }
        // .window gives us a real popover we can lay out freely (ARCHITECTURE.md).
        .menuBarExtraStyle(.window)
    }
}
