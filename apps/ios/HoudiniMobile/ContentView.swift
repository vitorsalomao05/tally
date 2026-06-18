import SwiftUI
import FetcherCore

/// The app's single screen. Mirrors the macOS popover: a stack of gauges with an
/// "updated X ago" footer, plus signed-out and error states. Refreshes on appear
/// and whenever the app returns to the foreground (there is no 60s timer on iOS —
/// PLAN.md §3).
struct ContentView: View {
    @StateObject private var model = UsageViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingLogin = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .signedOut:
                    signedOut
                case .loading where model.metrics.isEmpty:
                    ProgressView().tint(Theme.accent)
                default:
                    usage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Houdini")
            .toolbar {
                if model.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right",
                                   role: .destructive) { model.signOut() }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .sheet(isPresented: $showingLogin) {
            ClaudeLoginView { model.didSignIn() }
        }
    }

    // MARK: - States

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("See your Claude usage at a glance")
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Text("Sign in to claude.ai once. Your session stays in this device's Keychain — no server ever sees it.")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button { showingLogin = true } label: {
                Text("Sign in to Claude").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }

    private var usage: some View {
        ScrollView {
            VStack(spacing: 12) {
                if case .error(let message) = model.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(model.metrics, id: \.label) { GaugeRow(metric: $0) }
                if model.metrics.isEmpty, case .ok = model.state {
                    Text("No usage windows reported for this account.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 24)
                }
                if let updated = model.lastUpdated {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
                }
            }
            .padding(16)
        }
        .refreshable { model.refresh() }
    }
}

#Preview {
    ContentView()
}
