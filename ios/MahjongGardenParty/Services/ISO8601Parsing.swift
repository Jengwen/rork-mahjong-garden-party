import Foundation

/// Crash-safe ISO8601 timestamp parsing.
///
/// WHY THIS EXISTS
/// `ISO8601DateFormatter.date(from:)` is backed by ICU. When it fails in certain
/// ways — malformed input, unusual offsets, or heavy repeated use — ICU throws a
/// C++ exception. Swift cannot catch C++ exceptions, so the runtime calls
/// `abort()` and the app dies with SIGABRT. That is exactly the TestFlight crash
/// captured on 2026-09-05: `NSISO8601DateFormatter dateFromString` →
/// `icu::SimpleDateFormat::parse` → `__cxa_throw` → `abort()`, on the main thread,
/// inside a SwiftUI `ForEach` row body that re-parsed a timestamp on every update.
///
/// `Date.ISO8601FormatStyle` (iOS 15+, pure Swift in modern Foundation) parses
/// without going through ICU's throwing paths — a bad string returns nil instead
/// of killing the process. Everything here is `let`-only and value-typed, so it is
/// also safe to call from any thread, unlike a shared DateFormatter instance.
///
/// USE THIS instead of `ISO8601DateFormatter` anywhere a timestamp is parsed.
enum ISO8601 {

    // Supabase/Postgres emit a few shapes: "…Z", "…+00:00", with or without
    // fractional seconds. Try them in order of likelihood; each is a cheap
    // value type, so there is no formatter allocation cost to worry about.
    private static let strategies: [Date.ISO8601FormatStyle] = [
        Date.ISO8601FormatStyle(includingFractionalSeconds: true),
        Date.ISO8601FormatStyle(includingFractionalSeconds: false),
        Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true),
        Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: false)
    ]

    /// Parse an ISO8601 timestamp. Returns nil on anything unparseable — never traps.
    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        for strategy in strategies {
            if let date = try? Date(string, strategy: strategy) {
                return date
            }
        }
        return nil
    }

    /// Current time as an ISO8601 string. Matches the output of
    /// `ISO8601DateFormatter().string(from:)` ("2026-09-05T18:02:00Z").
    static func now() -> String {
        Date().ISO8601Format()
    }

    /// Format a specific date as an ISO8601 string.
    static func string(from date: Date) -> String {
        date.ISO8601Format()
    }
}
