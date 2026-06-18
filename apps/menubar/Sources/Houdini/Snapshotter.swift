import SwiftUI
import AppKit
import FetcherCore

/// Headless `--snapshot <dir>` mode: render the real SwiftUI views (popover,
/// settings, menu bar label) to PNGs via `ImageRenderer`, in BOTH light and dark
/// appearances. Deterministic — no clicking/timing — and uses the same views the
/// running app does. Tries live usage first; if that fails (e.g. no Claude token
/// on this machine) it falls back to `PreviewData` so the populated UI is shown.
///
/// Note: `SettingsView` now uses native `Picker`/`Toggle` controls, which
/// `ImageRenderer` cannot draw — `settings-*.png` are therefore placeholders. The
/// popover (pure shapes) still renders faithfully. See `SettingsView` for why we
/// chose native controls over render fidelity.
enum Snapshotter {
    static func run(outputDir: String) {
        _ = NSApplication.shared // initialise AppKit so text/graphics render

        let live = fetchSync()
        let metrics: [UsageMetric]
        switch live {
        case .success(let m) where !m.isEmpty:
            metrics = m
        default:
            FileHandle.standardError.write(Data("live fetch unavailable — using sample data\n".utf8))
            metrics = PreviewData.sampleMetrics()
        }

        MainActor.assumeIsolated {
            render(metrics: metrics, dir: outputDir)
        }
        exit(0)
    }

    /// Bridge the async fetch into this synchronous CLI path. URLSession callbacks
    /// run off the main thread, so blocking here won't deadlock.
    private static func fetchSync() -> Result<[UsageMetric], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var out: Result<[UsageMetric], Error> = .success([])
        Task.detached {
            do { out = .success(try await ClaudeOAuthProvider().fetch()) }
            catch { out = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return out
    }

    @MainActor
    private static func render(metrics: [UsageMetric], dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Isolated defaults so a snapshot run never clobbers the user's real prefs.
        let settings = AppSettings(defaults: UserDefaults(suiteName: "houdini.snapshot") ?? .standard)
        settings.primaryMetric = .fiveHour // mirror the shipped default (out-of-the-box bar)
        settings.refreshInterval = 60
        let launch = LaunchAtLogin()
        let session = ClaudeSession(settings: settings)

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let model = UsageModel(previewResult: .success(metrics))

            writePNG(panel(UsagePopover(model: model, session: session)), to: "\(dir)/popover-\(suffix).png", scheme: scheme)
            writePNG(SettingsView(settings: settings, launch: launch, session: session),
                     to: "\(dir)/settings-\(suffix).png", scheme: scheme)
            writePNG(MenuBarPreview(model: model, settings: settings, scheme: scheme),
                     to: "\(dir)/menubar-\(suffix).png", scheme: scheme)
        }
        FileHandle.standardError.write(Data("snapshots (light+dark) written to \(dir)\n".utf8))
    }

    /// Wrap a view in an opaque, appearance-adaptive panel so the PNG isn't
    /// transparent (the live popover gets this from the system window material).
    private static func panel(_ view: some View) -> some View {
        view.background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    private static func writePNG(_ view: some View, to path: String, scheme: ColorScheme) {
        // Drive both layers: NSAppearance so dynamic NSColors resolve correctly,
        // and the SwiftUI colorScheme environment so semantic colors flip.
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to render \(path)\n".utf8))
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// A representative menu bar strip for the snapshot image (the live app uses
/// `MenuBarLabelContent` directly inside the system menu bar). The strip tone
/// follows the appearance so the colored label reads correctly in both modes.
private struct MenuBarPreview: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            MenuBarLabelContent(model: model, settings: settings).padding(.horizontal, 10)
        }
        .frame(width: 240, height: 24, alignment: .trailing)
        .padding(.vertical, 3)
        .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.92))
    }
}
