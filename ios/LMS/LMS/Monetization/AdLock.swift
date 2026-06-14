import Foundation

/// Process-wide mutex for fullscreen ads (mirrors darts adLock) — stops two
/// fullscreen ads stacking on screen at once. Acquire immediately before show;
/// release on dismiss/error.
@MainActor
enum AdLock {
    private static var showing = false
    static var isShowing: Bool { showing }

    /// Returns true if the lock was acquired (caller may show).
    static func acquire() -> Bool {
        if showing { return false }
        showing = true
        return true
    }

    static func release() { showing = false }
}
