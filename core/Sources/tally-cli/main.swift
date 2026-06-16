import Foundation
import FetcherCore

// tally-cli — Phase 1 validation tool (ROADMAP.md).
// Fetches the "claude" provider snapshot and prints it as readable JSON to stdout.
// No UI, no colors. NEVER prints the OAuth token.
//
// Usage:
//   tally-cli            → fetch provider "claude"
//   tally-cli <id>       → fetch a specific provider id

func emitError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let providerId = CommandLine.arguments.dropFirst().first ?? "claude"
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
