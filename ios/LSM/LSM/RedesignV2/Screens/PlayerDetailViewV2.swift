import SwiftUI
import SwiftData

/// Card restyle of `PlayerDetailView` — same actions/scope as the original
/// (rename, mint/regenerate/remove submission link, QR code, "View as"/Share,
/// group membership, remove player). Logic (link state machine, rename-
/// cascade, mint/regenerate/remove) copied rather than shared with the
/// original, matching the precedent set by `OpenRoundViewV2`/`GameDetailViewV2`
/// — the v1 screen is a `List`-based `View` with its own `@State`, not
/// something a second `View` can reach into. `GroupMembershipEditorView` and
/// `PlayerLinkShareView` are reused as-is (unstyled, out of scope — same
/// precedent as `AddManualFixtureSheet` in `OpenRoundViewV2`). The original
/// view is untouched.
struct PlayerDetailViewV2: View {
    @Bindable var member: RosterMember
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    let pwaEnabled: Bool

    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var linkOp: LinkOpStateV2 = .idle
    @State private var linkShareItem: PlayerLinkShareItem?
    @State private var showGroupEditor = false
    @State private var pendingRemove = false
    @State private var pendingRemoveLink = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var showingLinkLimit = false
    @Query private var allMembers: [RosterMember]

    /// Total PWA links currently minted across the whole roster — a link is
    /// per-`RosterMember`, shared across every game that player is in, so
    /// this count already matches `maxPWALinks`' "across all games combined"
    /// definition with no double counting.
    private var activeLinkCount: Int { allMembers.filter { $0.submissionTokenRaw != nil }.count }

    private var atLinkLimit: Bool {
        guard let max = entitlements.maxPWALinks else { return false }
        return activeLinkCount >= max
    }

    private var linkURL: URL? {
        member.submissionToken.map { SubmissionsClient.playerLinkURL(token: $0.uuidString) }
    }

    private var isBusy: Bool {
        switch linkOp {
        case .revoking, .minting: return true
        case .idle, .error: return false
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                infoCard
                if pwaEnabled { linkCard }
                if let url = linkURL, let qrImage = QRCodeGenerator.image(for: url.absoluteString) {
                    qrCard(image: qrImage)
                }
                groupsCard
                Card(floating: true) {
                    ActionRow(title: "Remove Player", icon: "trash", tint: V2Theme.danger) { pendingRemove = true }
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TeamRoomScene()
        .v2FloatingHeader(member.name) {
            Button {
                renameText = member.name
                renaming = true
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(V2Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(V2Theme.cardBackground, in: Circle())
            }
        }
        .alert("Rename player", isPresented: $renaming) {
            TextField("Player name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $linkShareItem) { item in
            PlayerLinkShareView(item: item)
        }
        .sheet(isPresented: $showGroupEditor) {
            GroupMembershipEditorView(member: member)
        }
        .confirmationDialog(
            "Remove \(member.name)?",
            isPresented: $pendingRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                RosterMemberLifecycleService.delete(member, context: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also deactivates their submission link, if they have one.")
        }
        .confirmationDialog(
            "Remove \(member.name)'s link?",
            isPresented: $pendingRemoveLink,
            titleVisibility: .visible
        ) {
            Button("Remove Link", role: .destructive) { removeLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fully deactivates their PWA submission link, across every game they're in. They'll need a new link before they can submit again.")
        }
        .alert("Link limit reached", isPresented: $showingLinkLimit) {
            Button("OK", role: .cancel) {}
        } message: {
            if let max = entitlements.maxPWALinks {
                Text("Your \(entitlements.tier.label) plan includes \(max) player links. Remove an existing link or upgrade to add more.")
            }
        }
    }

    // MARK: - Cards

    private var infoCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 6) {
                if pwaEnabled {
                    if linkURL != nil {
                        Label("Link active", systemImage: "link")
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.accent)
                    } else {
                        Text("No link")
                            .font(V2Theme.Typography.metadata)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                Text("Created \(member.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textTertiary)
            }
        }
    }

    private var linkCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Submission Link")
                if let url = linkURL {
                    HStack(spacing: 8) {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(V2Theme.textSecondary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .foregroundStyle(V2Theme.accent)
                    }
                }
                linkOpContent
                if let url = linkURL {
                    ActionRow(title: "View as \(member.name)", icon: "eye") {
                        UIApplication.shared.open(url)
                    }
                    ActionRow(title: "Share Link", icon: "square.and.arrow.up", isEnabled: !isBusy) {
                        linkShareItem = PlayerLinkShareItem(playerName: member.name, url: url)
                    }
                    ActionRow(title: "Regenerate Link", icon: "arrow.triangle.2.circlepath", isEnabled: !isBusy) {
                        regenerateLink()
                    }
                    ActionRow(title: "Remove Link", icon: "link.badge.minus", tint: V2Theme.danger, isEnabled: !isBusy) {
                        pendingRemoveLink = true
                    }
                }
                if showMintFooter {
                    Text("Mint a personal link for this player. One link works across all their games.")
                        .font(.caption).foregroundStyle(V2Theme.textTertiary)
                } else if linkURL != nil {
                    Text(PlayerLinkShareItem.safetyWarning)
                        .font(.caption).foregroundStyle(V2Theme.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var linkOpContent: some View {
        switch linkOp {
        case .revoking:
            HStack(spacing: 8) { ProgressView(); Text("Deactivating old link…").foregroundStyle(V2Theme.textSecondary) }
        case .minting:
            HStack(spacing: 8) { ProgressView(); Text("Getting link…").foregroundStyle(V2Theme.textSecondary) }
        case .error(let message):
            Text(message).font(.caption).foregroundStyle(V2Theme.danger)
            if linkURL == nil {
                ActionRow(title: "Get Submission Link", icon: "link.badge.plus") { attemptMintLink() }
            }
        case .idle:
            if linkURL == nil {
                ActionRow(title: "Get Submission Link", icon: "link.badge.plus") { attemptMintLink() }
            }
        }
    }

    private func qrCard(image: UIImage) -> some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Show In Person", subtitle: "Face to face with this player? Show them this screen and let them scan it with their own camera.")
                HStack {
                    Spacer()
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                    Spacer()
                }
            }
        }
    }

    private var groupsCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Groups")
                    Spacer()
                    Button("Edit") { showGroupEditor = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.accent)
                }
                if member.groups.isEmpty {
                    Text("Not in any groups yet.")
                        .font(.caption).foregroundStyle(V2Theme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(member.groups.sorted { $0.name < $1.name }) { group in
                            Text(group.name)
                                .font(V2Theme.Typography.rowTitle)
                                .foregroundStyle(V2Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions (verbatim from `PlayerDetailView`)

    private var showMintFooter: Bool {
        guard linkURL == nil else { return false }
        if case .idle = linkOp { return true }
        return false
    }

    /// Renames the roster member and cascades the new name to every per-game
    /// `Player` stamped from them, across every game and mode — the roster
    /// member is the one global player identity; games just copy its name in.
    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let isDuplicate = allMembers.contains {
            $0.id != member.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !isDuplicate else { return }
        member.name = name

        let memberId = member.id
        let fd = FetchDescriptor<Player>(predicate: #Predicate { $0.rosterMemberId == memberId })
        if let players = try? context.fetch(fd) {
            for player in players { player.name = name }
        }

        // player_tokens.player_name only updates server-side inside a push's
        // players[] loop — now that Predictor/Killer round-opens can omit
        // that array entirely, a rename needs its own push to reach the
        // server rather than riding along with the next full-roster one.
        if member.submissionTokenRaw != nil {
            Task { await PWARoundPusher.pushSinglePlayerIfNeeded(rosterMember: member, context: context) }
        }
    }

    private func attemptMintLink() {
        if atLinkLimit {
            showingLinkLimit = true
        } else {
            mintLink()
        }
    }

    private func mintLink() {
        guard !isBusy else { return }
        linkOp = .minting
        let name = member.name
        let trimmedManagerName = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let token = try await SubmissionsClient.shared.mintLink(playerName: name, managerName: trimmedManagerName)
                await MainActor.run {
                    member.submissionTokenRaw = token.lowercased()
                    linkOp = .idle
                }
                await PWARoundPusher.pushSinglePlayerIfNeeded(rosterMember: member, context: context)
            } catch let error as APIError {
                if case .badStatus(409, _) = error {
                    await retryMintAfterRevokeByName(name: name, managerName: trimmedManagerName)
                } else {
                    await MainActor.run { linkOp = .error("Couldn't get a link. Try again.") }
                }
            } catch {
                await MainActor.run { linkOp = .error("Couldn't get a link. Try again.") }
            }
        }
    }

    private func retryMintAfterRevokeByName(name: String, managerName: String) async {
        do {
            try await SubmissionsClient.shared.revokeLinkByName(playerName: name)
            let token = try await SubmissionsClient.shared.mintLink(playerName: name, managerName: managerName)
            await MainActor.run {
                member.submissionTokenRaw = token.lowercased()
                linkOp = .idle
            }
            await PWARoundPusher.pushSinglePlayerIfNeeded(rosterMember: member, context: context)
        } catch {
            await MainActor.run {
                linkOp = .error("A link already exists for this player under a different manager — ask them to revoke it, or use a different player name.")
            }
        }
    }

    private func regenerateLink() {
        guard !isBusy, let oldToken = member.submissionTokenRaw else { return }
        linkOp = .revoking
        let name = member.name
        let trimmedManagerName = managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await SubmissionsClient.shared.revokeLink(token: oldToken)
            } catch {
                await MainActor.run {
                    linkOp = .error("Couldn't create a new link — the old one is still active. Try again.")
                }
                return
            }
            await MainActor.run { member.submissionTokenRaw = nil }
            do {
                let newToken = try await SubmissionsClient.shared.mintLink(playerName: name, managerName: trimmedManagerName)
                await MainActor.run {
                    member.submissionTokenRaw = newToken.lowercased()
                    linkOp = .idle
                }
                await PWARoundPusher.pushSinglePlayerIfNeeded(rosterMember: member, context: context)
            } catch {
                await MainActor.run {
                    linkOp = .error("The old link stopped working, but we couldn't create a new one. Tap Get Submission Link to try again.")
                }
            }
        }
    }

    private func removeLink() {
        guard !isBusy, let token = member.submissionTokenRaw else { return }
        linkOp = .revoking
        Task {
            do {
                try await SubmissionsClient.shared.revokeLink(token: token)
                await MainActor.run {
                    member.submissionTokenRaw = nil
                    linkOp = .idle
                }
            } catch {
                await MainActor.run {
                    linkOp = .error("Couldn't remove the link. Try again.")
                }
            }
        }
    }
}

private enum LinkOpStateV2: Equatable {
    case idle
    case revoking
    case minting
    case error(String)
}
