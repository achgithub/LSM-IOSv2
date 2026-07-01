import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Player-roster administration, moved out of the Players tab so that screen
/// can stay a lean browse/search list: turning player submission links on,
/// creating/renaming/deleting groups, and CSV import/export of the roster.
struct RosterManagementSection: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Query(sort: \RosterMember.name) private var members: [RosterMember]
    @Query(sort: \PlayerGroup.name) private var groups: [PlayerGroup]

    @AppStorage("pwaSubmissionsEnabled") private var pwaSubmissionsEnabled = false

    @State private var newGroup = ""
    @State private var renameTarget: PlayerGroup?
    @State private var renameText = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var importGroupId: UUID?
    @State private var message: String?
    @State private var showPaywall = false

    private var trimmedGroup: String { newGroup.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedRename: String { renameText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            Section {
                if entitlements.canUseCloud {
                    Toggle("Player submission links", isOn: $pwaSubmissionsEnabled)
                } else {
                    Button("Unlock Player Submission Links") { showPaywall = true }
                }
            } header: {
                Text("PWA Submissions")
            } footer: {
                Text(entitlements.canUseCloud
                     // swiftlint:disable:next line_length
                     ? "When on, you can share a personal link with each player so they can submit picks themselves. You review and approve before anything goes live."
                     : "Share a personal link with each player so they can submit picks from their phone. Requires the Cloud Bundle.")
            }

            Section("Groups (\(groups.count))") {
                HStack {
                    TextField("New group name", text: $newGroup)
                        .onSubmit(addGroup)
                    Button("Add", action: addGroup)
                        .disabled(trimmedGroup.isEmpty || isDuplicateGroup(trimmedGroup))
                }
                ForEach(groups) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.members.count)").foregroundStyle(.secondary)
                        Button("Rename") {
                            renameTarget = group
                            renameText = group.name
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete(perform: deleteGroups)
            }

            Section("Import / Export Players") {
                if !groups.isEmpty {
                    Picker("Import into group", selection: $importGroupId) {
                        Text("No group").tag(UUID?.none)
                        ForEach(groups) { group in
                            Text(group.name).tag(UUID?.some(group.id))
                        }
                    }
                }
                Button { importing = true } label: {
                    Label("Import CSV", systemImage: "doc.text")
                }
                Button { exporting = true } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(members.isEmpty)
                // Single localized string key — can't wrap without changing the key.
                // swiftlint:disable:next line_length
                Text("One name per row. Add a group with `Name, Group`. Rows without one go to the selected import group above. `Name, Email` still works (email ignored).")
                    .font(.caption).foregroundStyle(.secondary)
                if let message {
                    Text(message).font(.caption)
                }
            }
        }
        .alert("Rename group", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Group name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $exporting,
            document: RosterCSVDocument(text: RosterCSV.serialize(members)),
            contentType: .commaSeparatedText,
            defaultFilename: "players"
        ) { result in
            switch result {
            case .success:
                message = members.count == 1
                    ? AppString("Exported 1 player.")
                    : AppString("Exported \(members.count) players.")
            case .failure(let error): message = AppString("Export failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: Groups

    private func isDuplicateGroup(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return groups.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func addGroup() {
        let name = trimmedGroup
        guard !name.isEmpty, !isDuplicateGroup(name) else { return }
        context.insert(PlayerGroup(name: name))
        newGroup = ""
    }

    private func deleteGroups(at offsets: IndexSet) {
        for index in offsets { context.delete(groups[index]) }
    }

    private func commitRename() {
        defer { renameTarget = nil }
        guard let group = renameTarget else { return }
        let name = trimmedRename
        guard !name.isEmpty, !isDuplicateGroup(name) || name.localizedCaseInsensitiveCompare(group.name) == .orderedSame else { return }
        group.name = name
    }

    // MARK: CSV import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = AppString("Import failed: \(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                importRows(RosterCSV.parse(text))
            } catch {
                message = AppString("Couldn't read file: \(error.localizedDescription)")
            }
        }
    }

    /// Insert new (case-insensitively unique) members, resolve/create groups on
    /// the fly, and assign each member to its per-row group or the fallback.
    private func importRows(_ rows: [RosterCSV.Row]) {
        var membersByName = Dictionary(members.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var groupsByName = Dictionary(groups.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let fallbackGroupName = importGroupId.flatMap { id in groups.first { $0.id == id }?.name }

        func resolveGroup(_ name: String) -> PlayerGroup {
            let key = name.lowercased()
            if let existing = groupsByName[key] { return existing }
            let created = PlayerGroup(name: name)
            context.insert(created)
            groupsByName[key] = created
            return created
        }

        var added = 0, skipped = 0, assigned = 0
        for row in rows {
            let key = row.name.lowercased()
            let member: RosterMember
            if let existing = membersByName[key] {
                member = existing
                skipped += 1
            } else {
                member = RosterMember(name: row.name)
                context.insert(member)
                membersByName[key] = member
                added += 1
            }

            if let groupName = row.group ?? fallbackGroupName {
                let group = resolveGroup(groupName)
                if !member.groups.contains(where: { $0.id == group.id }) {
                    member.groups.append(group)
                    assigned += 1
                }
            }
        }

        var parts = [added == 1
                     ? AppString("Imported 1 new player")
                     : AppString("Imported \(added) new players")]
        if skipped > 0 {
            parts.append(skipped == 1
                         ? AppString("1 already existed")
                         : AppString("\(skipped) already existed"))
        }
        if assigned > 0 {
            parts.append(assigned == 1
                         ? AppString("1 group assignment")
                         : AppString("\(assigned) group assignments"))
        }
        // List separator is locale-aware; the parts are full clauses per language.
        message = parts.joined(separator: ", ") + "."
    }
}

/// Plain-text CSV document for `.fileExporter` — mirrors the `.fileImporter`
/// content types already used for import.
struct RosterCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
