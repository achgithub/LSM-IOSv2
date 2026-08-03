import Foundation

/// A small rolling diagnostic log, written to at the app's few network-error
/// chokepoints (`APIClient`, `AppAttestService`, `SubmissionsClient`) so the
/// raw detail behind a friendly on-screen error message isn't lost — it's
/// captured here instead, for a manager to attach via Settings → Report a
/// Bug. Caches-directory-backed (not iCloud, ephemeral only), trimmed to the
/// most recent ~150KB so it never grows unbounded.
///
/// An `actor` (not a plain enum with static funcs) because multiple network
/// calls can fail and log concurrently — actor isolation serializes the
/// file read/append/trim instead of racing on it.
actor DiagnosticLog {
    static let shared = DiagnosticLog()

    private let maxBytes = 150_000
    private let url: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("diagnostic.log")
    }()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    func log(_ message: String, category: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] [\(category)] \(message)\n"
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        existing += line
        if existing.utf8.count > maxBytes {
            // Trim from the front, keeping only the most recent ~maxBytes —
            // cheap approximation (character count, not exact UTF-8 byte
            // slicing) which is fine for a human-readable diagnostic log.
            existing = String(existing.suffix(maxBytes))
        }
        try? existing.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The log's current contents, for attaching to a bug report.
    func recentText() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "(no diagnostic log recorded yet)"
    }
}
