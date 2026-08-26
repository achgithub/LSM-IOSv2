import SwiftUI

/// Small pill label for a status or category — e.g. a game's mode (LMS,
/// Predictor, Killer) or its lifecycle state (Setup, Active, Complete).
struct V2StatusBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
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
        case .setup: self.init(label: status.label, tint: V2Theme.warning)
        case .active: self.init(label: status.label, tint: V2Theme.accent)
        case .complete: self.init(label: status.label, tint: V2Theme.textSecondary)
        }
    }
}
