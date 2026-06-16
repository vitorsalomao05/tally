import SwiftUI
import AppKit
import FetcherCore

/// Headless `--snapshot <dir>` mode: fetch live usage, render the real SwiftUI
/// views (popover + menu bar label) to PNGs via `ImageRenderer`, then exit.
/// Deterministic — no clicking/timing needed — and uses the same views/data as
/// the running app.
enum Snapshotter {
    static func run(outputDir: String) {
        _ = NSApplication.shared // initialise AppKit so text/graphics render

        let result = fetchSync()
        MainActor.assumeIsolated {
            let model = UsageModel(previewResult: result)
            render(model: model, dir: outputDir)
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
    private static func render(model: UsageModel, dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        writePNG(UsagePopover(model: model), to: "\(dir)/popover.png")
        writePNG(MenuBarPreview(model: model), to: "\(dir)/menubar.png")
        FileHandle.standardError.write(Data("snapshots written to \(dir)\n".utf8))
    }

    @MainActor
    private static func writePNG(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
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

/// A representative dark menu bar strip, just for the snapshot image (the live
/// app uses `MenuBarLabelContent` directly inside the system menu bar).
private struct MenuBarPreview: View {
    @ObservedObject var model: UsageModel
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            MenuBarLabelContent(model: model).padding(.horizontal, 10)
        }
        .frame(width: 240, height: 24, alignment: .trailing)
        .padding(.vertical, 3)
        .background(Color(white: 0.13))
    }
}
