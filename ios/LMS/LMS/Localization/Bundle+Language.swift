import Foundation

/// In-app language override. By default `Bundle.main` resolves localized strings
/// against the device language; to let the user pick a language *inside* the app
/// we re-point `Bundle.main` at a specific `.lproj` so `String(localized:)`,
/// `NSLocalizedString`, and SwiftUI's `Text(LocalizedStringKey)` all resolve in
/// the chosen language immediately — no relaunch.
///
/// Done by swapping `Bundle.main`'s class to a subclass that overrides string
/// lookup. This is the standard, App Store–safe technique (no private API).
private var languageBundleKey: UInt8 = 0

private final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &languageBundleKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Point `Bundle.main` at the `.lproj` for `code` (e.g. "es"), or pass `nil`
    /// to fall back to the device language. Safe to call repeatedly.
    static func setAppLanguage(_ code: String?) {
        // Swap the class once so string lookups route through the override.
        if !(Bundle.main is LanguageOverrideBundle) {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
        }
        let path = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, path, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
