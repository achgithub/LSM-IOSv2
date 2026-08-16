import SwiftUI
import SwiftData

/// The manager's own identity: display name, optional recovery email, and
/// the list of this account's cloud games available to pull onto this
/// device. Combines what used to be three separate rows (Profile, Account,
/// Sync Games) into one screen — the split never explained itself well
/// ("why is there a whole separate 'Account' screen, and what does 'Sync
/// Games' even mean here?"). Free for every tier: the email is a safety net
/// that costs nothing until it's actually needed, gating it behind a
/// subscription only reaches the people who won't need it and misses the
/// free-tier user who loses their phone before ever upgrading.
struct ProfileSettingsView: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""
    @Environment(\.modelContext) private var context
    @State private var syncModel = GameSyncListModel()

    @State private var emailDraft = ""
    @State private var otpDraft = ""
    @State private var emailStage: EmailStage = .enterEmail
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum EmailStage {
        case enterEmail
        case enterCode(email: String)
    }

    var body: some View {
        List {
            Section {
                TextField("Your name", text: $managerName)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("You're added to games you create, and your pick is always shown on shared summary cards.")
            }

            emailSection

            gamesSection
        }
        .appBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await syncModel.load(context: context) }
        .alert("Couldn't Complete That", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Email

    @ViewBuilder
    private var emailSection: some View {
        if !linkedEmail.isEmpty {
            Section {
                LabeledContent("Registered email", value: linkedEmail)
            } footer: {
                Text("If you get a new phone, enter this email during setup to recover your games.")
            }
            Section {
                Button("Use a Different Email", role: .destructive) {
                    linkedEmail = ""
                    emailStage = .enterEmail
                    emailDraft = ""
                    otpDraft = ""
                }
            }
        } else {
            switch emailStage {
            case .enterEmail:
                Section {
                    TextField("Email", text: $emailDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                } header: {
                    Text("Email (optional)")
                } footer: {
                    Text("Register your email so you can recover your games on a new device if you ever lose this one.")
                }
                Section {
                    Button {
                        Task { await sendCode() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Send Code") }
                    }
                    .disabled(isBusy || !isPlausibleEmail(emailDraft))
                }

            case .enterCode(let email):
                Section {
                    LabeledContent("Email", value: email)
                    TextField("6-digit code", text: $otpDraft)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Enter the code we just sent to \(email).")
                }
                Section {
                    Button {
                        Task { await verifyCode(email: email) }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Verify") }
                    }
                    .disabled(isBusy || otpDraft.count != 6)

                    Button("Use a Different Email") {
                        emailStage = .enterEmail
                        otpDraft = ""
                    }
                }
            }
        }
    }

    private func isPlausibleEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".") && value.count > 4
    }

    private func sendCode() async {
        let email = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isPlausibleEmail(email) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AccountClient.shared.registerRequest(email: email)
            emailStage = .enterCode(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode(email: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AccountClient.shared.registerVerify(email: email, otp: otpDraft)
            linkedEmail = email
            emailStage = .enterEmail
            emailDraft = ""
            otpDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Games

    @ViewBuilder
    private var gamesSection: some View {
        if let loadError = syncModel.loadError {
            Section("Your Games") {
                Text(loadError).foregroundStyle(.secondary)
                Button("Try Again") { Task { await syncModel.load(context: context) } }
            }
        } else if syncModel.isLoading {
            Section("Your Games") { ProgressView() }
        } else if !syncModel.games.isEmpty {
            Section {
                ForEach(syncModel.games) { game in
                    gameRow(game)
                }
            } header: {
                Text("Your Games")
            } footer: {
                Text("Pick a game to bring it to this device. You can come back later for the rest.")
            }
        }
    }

    @ViewBuilder
    private func gameRow(_ game: RemoteGameSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.gameName?.isEmpty == false ? game.gameName! : AppString("Untitled Game"))
                        .font(.body)
                    Text("\(game.mode.capitalized) · Round \(game.roundNumber)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                gameTrailingControl(for: game)
            }
            if let message = syncModel.errorsByToken[game.gameToken] {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func gameTrailingControl(for game: RemoteGameSummary) -> some View {
        if syncModel.isLocal(game) {
            Label("On This Device", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if syncModel.syncingTokens.contains(game.gameToken) {
            ProgressView()
        } else {
            Button("Sync") { syncModel.sync(game, context: context) }
                .buttonStyle(.bordered)
        }
    }
}
