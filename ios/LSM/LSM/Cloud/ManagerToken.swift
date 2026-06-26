import Foundation

/// Stable anonymous device identifier for cloud lifecycle management.
/// Generated once on first cloud use and persisted in UserDefaults.
/// Sent with every push, mint, and backup so the worker can attribute
/// all cloud data to this manager for cleanup and lifecycle tracking.
enum ManagerToken {
    private static let key = "lsmManagerCloudToken"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString.lowercased()
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
