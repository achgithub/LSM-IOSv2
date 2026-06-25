import Foundation
import SwiftData

#if DEBUG
/// DEBUG-only convenience: seeds 10 placeholder roster players on the very
/// first launch of a dev build, so a fresh install/reinstall during testing
/// doesn't mean retyping a roster every time. Never compiled into a
/// Release/TestFlight/App Store build — real customers never see this.
///
/// One-time via a UserDefaults flag (not "seed if roster is empty"), so
/// deleting some or all of them doesn't bring them back on the next launch —
/// they're just a starting point, like any other roster entry.
enum DemoRosterSeeder {
    private static let seededKey = "debugDidSeedDemoRoster"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)
        for n in 1...10 {
            context.insert(RosterMember(name: "Demo Player \(n)"))
        }
    }
}
#endif
