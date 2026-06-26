import SwiftUI
import SwiftData

private enum PredictorSheet: String, Identifiable {
    case open, predictions, results, standings, publish, submissions
    var id: String { rawValue }
}

/// Predictor game detail: same shell as `GameDetailView` (info/roster) but
/// without any of the LMS-specific elimination/tie-resolution machinery —
/// every player just accumulates points round over round, indefinitely.
struct PredictorGameDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Bindable var game: Game
    @State private var showingAddPlayers = false
    @State private var sheet: PredictorSheet?
    @State private var pendingRemovePlayer: Player?
    @State private var pendingEditFixtures = false

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false
    @State private var pendingLinkPlayer: Player?
    @State private var pendingRevokePlayer: Player?
    @State private var linkShareItem: PlayerLinkShareItem?
    @State private var isMintingLink = false

    private var sortedPlayers: [Player] {
        game.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var currentRound: Round? { game.currentRound }
    private var openRound: Round? {
        if let round = currentRound, round.status != .closed { return round }
        return nil
    }
    private var latestClosedRound: Round? {
        game.rounds.filter { $0.status == .closed }.max(by: { $0.roundNumber < $1.roundNumber })
    }

    var body: some View {
        List {
            infoSection
            roundSection
            playersSection
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPlayers) { AddPlayersView(game: game) }
        .sheet(item: $sheet) { which in
            switch which {
            case .open:
                OpenRoundView(game: game)
            case .predictions:
                if let round = openRound { PredictionsEntryView(game: game, round: round) }
            case .results:
                if let round = openRound { PredictorResultsEntryView(game: game, round: round) }
            case .standings:
                NavigationStack { PredictorStandingsView(game: game) }
            case .publish:
                PublishPredictorView(game: game)
            case .submissions:
                if let round = openRound, let gameToken = game.cloudGameToken {
                    NavigationStack {
                        SubmissionQueueView(game: game, round: round, gameToken: gameToken)
                    }
                }
            }
        }
        .background(linkDialogHost)
        .confirmationDialog(
            "Remove \(pendingRemovePlayer?.name ?? "")?",
            isPresented: Binding(get: { pendingRemovePlayer != nil }, set: { if !$0 { pendingRemovePlayer = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemovePlayer
        ) { player in
            Button("Remove \(player.name)", role: .destructive) { removePlayer(player) }
            Button("Cancel", role: .cancel) {}
        } message: { player in
            Text("\(player.name) is removed from the game and their predictions deleted. This can't be undone.")
        }
        .confirmationDialog(
            "Edit fixtures?",
            isPresented: $pendingEditFixtures,
            titleVisibility: .visible
        ) {
            Button("Edit Fixtures", role: .destructive) { resetOpenRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the round so you can reselect fixtures. Any predictions already entered are cleared. This can't be undone.")
        }
    }

    private var infoSection: some View {
        Section {
            LabeledContent("Status", value: game.status.label)
            LabeledContent("Matchday", value: "\(currentRound?.roundNumber ?? 0)")
            Button { sheet = .standings } label: {
                Label("Standings", systemImage: "list.number")
            }
            if entitlements.canUseCloud {
                Button { sheet = .publish } label: {
                    Label("Publish League…", systemImage: "globe")
                }
            }
        }
    }

    @ViewBuilder
    private var roundSection: some View {
        Section("This Matchday") {
            if let round = openRound {
                LabeledContent("Matchday \(round.roundNumber)", value: round.status.label)
                Button(role: .destructive) { pendingEditFixtures = true } label: {
                    Label("Edit Fixtures", systemImage: "pencil")
                }
                Button { sheet = .predictions } label: { Label("Enter Predictions", systemImage: "checklist") }
                Button { sheet = .results } label: { Label("Enter Results / Close", systemImage: "flag.checkered") }
                if pwaSubmissionsEnabled, game.cloudGameToken != nil {
                    Button { sheet = .submissions } label: {
                        Label("Submission Queue", systemImage: "tray.and.arrow.down")
                    }
                }
            } else {
                Button { sheet = .open } label: { Label("Open Matchday", systemImage: "calendar.badge.plus") }
                    .disabled(game.players.isEmpty)
            }
        }
    }

    private var playersSection: some View {
        Section("Players (\(game.players.count))") {
            if game.players.isEmpty {
                Text("No players yet.").foregroundStyle(.secondary)
            } else {
                ForEach(sortedPlayers) { player in
                    HStack {
                        Text(player.name)
                        if player.isManager {
                            Text("you")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        if pwaSubmissionsEnabled, !player.isManager {
                            Button {
                                if player.submissionToken != nil {
                                    pendingLinkPlayer = player
                                } else {
                                    mintLink(for: player, regenerate: false)
                                }
                            } label: {
                                Image(systemName: player.submissionToken != nil ? "link" : "link.badge.plus")
                                    .foregroundStyle(player.submissionToken != nil ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingRemovePlayer = player } label: {
                            Label("Remove", systemImage: "person.fill.xmark")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if pwaSubmissionsEnabled, !player.isManager {
                            Button {
                                if player.submissionToken != nil {
                                    pendingLinkPlayer = player
                                } else {
                                    mintLink(for: player, regenerate: false)
                                }
                            } label: {
                                Label(player.submissionToken != nil ? "Link" : "Get Link",
                                      systemImage: "link")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            Button { showingAddPlayers = true } label: {
                Label("Add Players", systemImage: "person.badge.plus")
            }
        }
    }

    private func removePlayer(_ player: Player) {
        game.players.removeAll { $0.id == player.id }
        context.delete(player)
        pendingRemovePlayer = nil
    }

    private func resetOpenRound() {
        guard let round = openRound else { return }
        game.rounds.removeAll { $0.id == round.id }
        context.delete(round)
    }

    // MARK: - PWA Submissions

    @ViewBuilder
    private var linkDialogHost: some View {
        Color.clear
            .sheet(item: $linkShareItem) { item in
                ActivityShareView(items: item.shareItems)
            }
            .confirmationDialog(
                "Link for \(pendingLinkPlayer?.name ?? "")",
                isPresented: Binding(
                    get: { pendingLinkPlayer != nil },
                    set: { if !$0 { pendingLinkPlayer = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingLinkPlayer
            ) { player in
                Button("Share Link") { shareLink(for: player) }
                Button("Regenerate Link", role: .destructive) { mintLink(for: player, regenerate: true) }
                Button("Revoke Link", role: .destructive) { revokeLink(for: player) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Revoke link for \(pendingRevokePlayer?.name ?? "")?",
                isPresented: Binding(
                    get: { pendingRevokePlayer != nil },
                    set: { if !$0 { pendingRevokePlayer = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingRevokePlayer
            ) { player in
                Button("Revoke", role: .destructive) { confirmRevokeLink(for: player) }
                Button("Cancel", role: .cancel) {}
            } message: { player in
                Text("\(player.name)'s link stops working immediately. You can mint a new one at any time.")
            }
    }

    private func playerLinkURL(for player: Player) -> URL? {
        guard let token = player.submissionToken else { return nil }
        return URL(string: "https://lsm-uk-worker.sportsmanager.workers.dev/s/\(token.uuidString.lowercased())")
    }

    private func shareLink(for player: Player) {
        guard let url = playerLinkURL(for: player) else { return }
        pendingLinkPlayer = nil
        linkShareItem = PlayerLinkShareItem(playerName: player.name, url: url)
    }

    private func mintLink(for player: Player, regenerate: Bool) {
        guard !isMintingLink else { return }
        if game.cloudGameTokenRaw == nil {
            game.cloudGameTokenRaw = UUID().uuidString.lowercased()
        }
        guard let gameToken = game.cloudGameToken else { return }
        pendingLinkPlayer = nil
        isMintingLink = true
        let name = player.name
        Task {
            do {
                let token = try await SubmissionsClient.shared.mintLink(
                    gameToken: gameToken,
                    localPlayerId: player.id,
                    playerName: name
                )
                player.submissionTokenRaw = token.lowercased()
                let url = URL(string: "https://lsm-uk-worker.sportsmanager.workers.dev/s/\(token.lowercased())")
                await MainActor.run {
                    isMintingLink = false
                    if let url { linkShareItem = PlayerLinkShareItem(playerName: name, url: url) }
                }
            } catch {
                await MainActor.run { isMintingLink = false }
            }
        }
    }

    private func revokeLink(for player: Player) {
        pendingLinkPlayer = nil
        pendingRevokePlayer = player
    }

    private func confirmRevokeLink(for player: Player) {
        guard let gameToken = game.cloudGameToken,
              let token = player.submissionTokenRaw else { return }
        pendingRevokePlayer = nil
        let t = token
        Task { try? await SubmissionsClient.shared.revokeLink(gameToken: gameToken, token: t) }
        player.submissionTokenRaw = nil
    }
}
