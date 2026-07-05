import SwiftUI
import SwiftData
import UIKit

/// The reusable player roster hub (the second tab): browse, search, and filter
/// your players. Adding people to a game happens inside the game (Games → Add
/// Players), pulling from this roster. Roster administration — turning on
/// player links, creating/renaming/deleting groups, CSV import/export — lives
/// in Settings (`RosterManagementSection`) so this screen stays a lean list.
struct PlayersView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Query(sort: \RosterMember.name) private var members: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false

    @State private var searchText = ""
    @State private var groupFilter: UUID?
    @State private var linkFilter: LinkFilter = .all
    @State private var showAddPlayerAlert = false
    @State private var newPlayerName = ""

    private var pwaEnabled: Bool { entitlements.canUseCloud && pwaSubmissionsEnabled }

    private var filteredMembers: [RosterMember] {
        members.filter { member in
            (searchText.isEmpty || member.name.localizedCaseInsensitiveContains(searchText))
                && (groupFilter == nil || member.groups.contains { $0.id == groupFilter })
                && (!pwaEnabled || linkFilter == .all
                    || (linkFilter == .active) == (member.submissionTokenRaw != nil))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                filterSection
                playersSection
                infoSection
            }
            .appBackground()
            .navigationTitle("Players")
            .searchable(text: $searchText, prompt: "Search players...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddPlayerAlert = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add player")
                }
                ToolbarItem(placement: .primaryAction) {
                    if !members.isEmpty { EditButton() }
                }
            }
            .alert("Add player", isPresented: $showAddPlayerAlert) {
                TextField("Player name", text: $newPlayerName)
                Button("Add", action: addMember)
                    .disabled(trimmedNewName.isEmpty || isDuplicateMember(trimmedNewName))
                Button("Cancel", role: .cancel) { newPlayerName = "" }
            }
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        if !groups.isEmpty || pwaEnabled {
            Section {
                HStack {
                    if !groups.isEmpty {
                        Picker("Group", selection: $groupFilter) {
                            Text("All Groups").tag(UUID?.none)
                            ForEach(groups) { group in
                                Text(group.name).tag(UUID?.some(group.id))
                            }
                        }
                    }
                    if pwaEnabled {
                        Picker("Link status", selection: $linkFilter) {
                            ForEach(LinkFilter.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private var playersSection: some View {
        Section {
            if members.isEmpty {
                Text("No saved players yet. Add people here, then add them to a game.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if filteredMembers.isEmpty {
                Text("No players match.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(filteredMembers) { member in
                    NavigationLink {
                        PlayerDetailView(member: member, pwaEnabled: pwaEnabled)
                    } label: {
                        playerRow(member)
                    }
                }
                .onDelete(perform: deleteMembers)
            }
        } header: {
            Text("\(filteredMembers.count) player\(filteredMembers.count == 1 ? "" : "s")")
        }
    }

    private func playerRow(_ member: RosterMember) -> some View {
        HStack {
            Text(member.name)
            Spacer()
            if pwaEnabled {
                Image(systemName: member.submissionTokenRaw != nil ? "link" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        Section {
            Text(pwaEnabled
                 ? "Give each player a private link so they can submit picks themselves. You approve before it goes live."
                 : "Turn on player links in Settings to share a personal submission link with each player.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var trimmedNewName: String { newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func isDuplicateMember(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return members.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func addMember() {
        let name = trimmedNewName
        guard !name.isEmpty, !isDuplicateMember(name) else { return }
        context.insert(RosterMember(name: name))
        newPlayerName = ""
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets { RosterMemberLifecycleService.delete(members[index], context: context) }
    }
}

private enum LinkFilter: String, CaseIterable, Identifiable {
    case all, active, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All Players"
        case .active: return "Has Link"
        case .none: return "No Link"
        }
    }
}

/// One player's detail: link status, the submission link itself, and their
/// groups. Group membership editing and group creation/rename/delete live
/// elsewhere now (a sheet here, Settings for the latter).
struct PlayerDetailView: View {
    @Bindable var member: RosterMember
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let pwaEnabled: Bool

    @AppStorage(ManagerSettings.nameKey) private var managerName = ""

    @State private var linkOp: LinkOpState = .idle
    @State private var linkShareItem: PlayerLinkShareItem?
    @State private var showGroupEditor = false
    @State private var pendingRemove = false
    @State private var renaming = false
    @State private var renameText = ""
    @Query private var allMembers: [RosterMember]

    private var linkURL: URL? {
        member.submissionToken.map { SubmissionsClient.playerLinkURL(token: $0.uuidString) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(member.name).font(.headline)
                        Spacer()
                        Button("Rename") {
                            renameText = member.name
                            renaming = true
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    if pwaEnabled {
                        if linkURL != nil {
                            Label("Link active", systemImage: "link")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        } else {
                            Text("No link").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text("Created \(member.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if pwaEnabled {
                Section {
                    linkSectionContent
                } header: {
                    Text("Submission Link")
                } footer: {
                    if showMintFooter {
                        Text("Mint a personal link for this player. One link works across all their games.")
                    } else if linkURL != nil {
                        Text(PlayerLinkShareItem.safetyWarning)
                    }
                }

                if let url = linkURL, let qrImage = QRCodeGenerator.image(for: url.absoluteString) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Show In Person")
                    } footer: {
                        Text("Face to face with this player? Show them this screen and let them scan it with their own camera.")
                    }
                }

                if linkURL != nil {
                    Section {
                        Button {
                            guard let url = linkURL else { return }
                            linkShareItem = PlayerLinkShareItem(playerName: member.name, url: url)
                        } label: {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isBusy)

                        Button {
                            regenerateLink()
                        } label: {
                            Label("Regenerate Link", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isBusy)
                    }
                }
            }

            Section {
                if member.groups.isEmpty {
                    Text("Not in any groups yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(member.groups.sorted { $0.name < $1.name }) { group in
                        Text(group.name)
                    }
                }
            } header: {
                HStack {
                    Text("Groups")
                    Spacer()
                    Button("Edit") { showGroupEditor = true }
                        .font(.caption)
                }
            }

            Section {
                Button(role: .destructive) { pendingRemove = true } label: {
                    Text("Remove Player")
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
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
    }

    /// Renames the roster member and cascades the new name to every per-game
    /// `Player` stamped from them, across every game and mode — the roster
    /// member is the one global player identity; games just copy its name in.
    /// Shares/pushes read the name live, so nothing else needs to change here;
    /// the backend's cached copy self-heals on the next round push instead of
    /// a dedicated network call (see `OpenRoundView` push, `submissions.ts`).
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
    }

    private var isBusy: Bool {
        switch linkOp {
        case .revoking, .minting: return true
        case .idle, .error: return false
        }
    }

    private var showMintFooter: Bool {
        guard linkURL == nil else { return false }
        if case .idle = linkOp { return true }
        return false
    }

    @ViewBuilder
    private var linkSectionContent: some View {
        if let url = linkURL {
            HStack {
                Text(url.absoluteString)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        switch linkOp {
        case .revoking:
            HStack { ProgressView(); Text("Deactivating old link…").foregroundStyle(.secondary) }
        case .minting:
            HStack { ProgressView(); Text("Getting link…").foregroundStyle(.secondary) }
        case .error(let message):
            Text(message).font(.caption).foregroundStyle(.red)
            if linkURL == nil {
                Button { mintLink() } label: {
                    Label("Get Submission Link", systemImage: "link.badge.plus")
                }
            }
        case .idle:
            if linkURL == nil {
                Button { mintLink() } label: {
                    Label("Get Submission Link", systemImage: "link.badge.plus")
                }
            }
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
            } catch let error as APIError {
                await MainActor.run {
                    if case .badStatus(409, _) = error {
                        linkOp = .error("A link already exists for this player on another device. Revoke it there first, or ask your manager.")
                    } else {
                        linkOp = .error("Couldn't get a link. Try again.")
                    }
                }
            } catch {
                await MainActor.run { linkOp = .error("Couldn't get a link. Try again.") }
            }
        }
    }

    /// Revoke the old token, then mint a fresh one — properly sequenced (not
    /// fire-and-forget) so a failed mint after a successful revoke is reported
    /// distinctly rather than silently leaving the player linkless.
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
            } catch {
                await MainActor.run {
                    linkOp = .error("The old link stopped working, but we couldn't create a new one. Tap Get Submission Link to try again.")
                }
            }
        }
    }
}

private enum LinkOpState: Equatable {
    case idle
    case revoking
    case minting
    case error(String)
}

/// Toggle which groups a player belongs to — presented as a sheet from the
/// player detail's Groups section.
private struct GroupMembershipEditorView: View {
    @Bindable var member: RosterMember
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    Text("No groups yet — create one in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { group in
                        Button {
                            toggle(group)
                        } label: {
                            HStack {
                                Text(group.name).foregroundStyle(.primary)
                                Spacer()
                                if isMember(of: group) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isMember(of group: PlayerGroup) -> Bool {
        member.groups.contains { $0.id == group.id }
    }

    private func toggle(_ group: PlayerGroup) {
        if let index = member.groups.firstIndex(where: { $0.id == group.id }) {
            member.groups.remove(at: index)
        } else {
            member.groups.append(group)
        }
    }
}
