import Foundation
import FetcherCore

// houdini — Phase 1 validation tool (ROADMAP.md).
// Fetches the "claude" provider snapshot and prints it as readable JSON to stdout.
// No UI, no colors. NEVER prints the OAuth token.
//
// Usage:
//   houdini                 → fetch provider "claude"
//   houdini <id>            → fetch a specific provider id
//   houdini --json [<id>]   → same output; explicit flag so consumers (the
//                               Übersicht wrapper) can pin a stable contract.
//
// JSON is the only output mode, so `--json` is accepted and ignored. Any
// non-flag argument is taken as the provider id; unknown flags are ignored.

func emitError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())
let providerId = arguments.first { !$0.hasPrefix("-") } ?? "claude"
let registry = ProviderRegistry.makeDefault()

guard let provider = registry.provider(id: providerId) else {
    emitError("error: no provider registered with id '\(providerId)'")
    exit(64) // EX_USAGE
}

do {
    let snapshot = try await provider.snapshot()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601

    let json = try encoder.encode(snapshot)
    if let text = String(data: json, encoding: .utf8) {
        print(text)
    }
} catch let error as ProviderError {
    emitError("error: \(error)")
    exit(2)
} catch {
    emitError("error: \(error)")
    exit(1)
}
