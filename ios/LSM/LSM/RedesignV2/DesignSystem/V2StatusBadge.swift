import SwiftUI

/// Small pill label for a status or category — e.g. a game's mode (LMS,
/// Predictor, Killer) or its lifecycle state (Setup, Active, Complete).
struct V2StatusBadge: View {
    private let label: Text
    let tint: Color

    /// UI copy — goes through `Localizable.xcstrings`.
    init(label: LocalizedStringKey, tint: Color) {
        self.label = Text(label)
        self.tint = tint
    }

    /// For a status string already localized by its own `label` (see
    /// `Enums.swift`), which must not be looked up a second time.
    init(verbatim label: String, tint: Color) {
        self.label = Text(verbatim: label)
        self.tint = tint
    }

    var body: some View {
        label
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

extension V2StatusBadge {
    init(gameStatus status: GameStatus) {
        switch status {
        case .setup: self.init(verbatim: status.label, tint: V2Theme.warning)
        case .active: self.init(verbatim: status.label, tint: V2Theme.accent)
        case .complete: self.init(verbatim: status.label, tint: V2Theme.textSecondary)
        }
    }
}
