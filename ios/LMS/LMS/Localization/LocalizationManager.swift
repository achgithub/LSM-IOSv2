import Foundation
import SwiftUI
import Observation

/// The languages the app ships with. The display name is the language's own
/// endonym (English, Español, Deutsch…) and is intentionally NOT localized — a
/// language always lists itself the same way whatever the current selection is.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system          // follow the device language
    case english = "en"
    case spanish = "es"
    case german = "de"
    case french = "fr"
    case dutch = "nl"
    case italian = "it"

    var id: String { rawValue }

    /// The endonym shown in the Settings picker. Fixed per language — never
    /// translated. `.system` is the only entry that follows the UI language.
    var displayName: String {
        switch self {
        case .system:  return String(localized: "System Default")
        case .english: return "English"
        case .spanish: return "Español"
        case .german:  return "Deutsch"
        case .french:  return "Français"
        case .dutch:   return "Nederlands"
        case .italian: return "Italiano"
        }
    }

    /// The `.lproj` resource name, or nil for `.system` (use the device default).
    var resourceCode: String? { self == .system ? nil : rawValue }
}

/// Drives in-app language selection. Persists the choice and applies it live (no
/// restart) by swapping the bundle Foundation/SwiftUI read localized strings from
/// (see `Bundle.setAppLanguage`). The root view re-renders on change by keying on
/// `language` and injecting `locale` into the environment so dates/numbers follow.
@Observable @MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private static let storageKey = "app_language"

    private(set) var language: AppLanguage

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
        Bundle.setAppLanguage(language.resourceCode)
    }

    /// The locale used for `\.locale` so SwiftUI formats dates, numbers and
    /// plural-rule selection in the chosen language. `.system` follows the device.
    var locale: Locale {
        switch language.resourceCode {
        case let code?: return Locale(identifier: code)
        case nil:       return Locale.autoupdatingCurrent
        }
    }

    func select(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        Bundle.setAppLanguage(language.resourceCode)
    }
}
