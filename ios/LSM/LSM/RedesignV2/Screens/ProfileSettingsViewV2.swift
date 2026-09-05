import SwiftUI
import SwiftData

/// Card restyle of `ProfileSettingsView` — same merge (name, recovery email,
/// cloud games list) in one screen instead of three separate rows. See that
/// file's header comment for why the merge and why registering is gated to
/// cloud tiers.
struct ProfileSettingsViewV2: View {
    @AppStorage(ManagerSettings.nameKey) private var managerName = ""
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""
    @Environment(\.modelContext) private var context
    @State private var entitlements = Entitlements.shared
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
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Your Name")
                        TextField("Your name", text: $managerName)
                            .textInputAutocapitalization(.words)
                            .padding(12)
                            .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                        Text("You're added to games you create, and your pick is always shown on shared summary cards.")
                            .font(.caption)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }

                emailCard

                gamesCard
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .v2TacticsOfficeScene()
        .v2LoadingOverlay(syncModel.isLoading, label: "Loading games…")
        .v2FloatingHeader("Profile")
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
    private var emailCard: some View {
        if !linkedEmail.isEmpty {
            VStack(spacing: V2Theme.Spacing.section) {
                Card(floating: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Registered Email")
                        Text(linkedEmail)
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                        Text("If you get a new phone, enter this email during setup to recover your games.")
                            .font(.caption)
                            .foregroundStyle(V2Theme.textSecondary)
                    }
                }
                // Read-only below the cloud tiers: registering was ungated
                // before, so managers on Free/No Ads may already have an
                // email on file. Recovery keeps working for them (link-device
                // is never gated) — they just can't re-point it until they're
                // back on a cloud tier. Taking a safety net away from someone
                // who already has it is worse than not offering a new one.
                if entitlements.canUseCloud {
                    Button("Use a Different Email", role: .destructive) {
                        linkedEmail = ""
                        emailStage = .enterEmail
                        emailDraft = ""
                        otpDraft = ""
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        } else if !entitlements.canUseCloud {
            cloudUpsellCard
        } else {
            switch emailStage {
            case .enterEmail:
                VStack(spacing: V2Theme.Spacing.section) {
                    Card(floating: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Email (Optional)")
                            TextField("Email", text: $emailDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .padding(12)
                                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            Text("Register your email so you can recover your games on a new device if you ever lose this one.")
                                .font(.caption)
                                .foregroundStyle(V2Theme.textSecondary)
                        }
                    }
                    PrimaryButton(title: isBusy ? "Sending…" : "Send Code", isEnabled: !isBusy && isPlausibleEmail(emailDraft)) {
                        Task { await sendCode() }
                    }
                }

            case .enterCode(let email):
                VStack(spacing: V2Theme.Spacing.section) {
                    Card(floating: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Enter Code")
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(V2Theme.textSecondary)
                            TextField("6-digit code", text: $otpDraft)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(V2Theme.pillBackground, in: RoundedRectangle(cornerRadius: V2Theme.Radius.row, style: .continuous))
                            Text("Enter the code we just sent to \(email).")
                                .font(.caption)
                                .foregroundStyle(V2Theme.textSecondary)
                        }
                    }
                    PrimaryButton(title: isBusy ? "Verifying…" : "Verify", isEnabled: !isBusy && otpDraft.count == 6) {
                        Task { await verifyCode(email: email) }
                    }
                    Button("Use a Different Email") {
                        emailStage = .enterEmail
                        otpDraft = ""
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(V2Theme.accent)
                }
            }
        }
    }

    /// What Free/No Ads sees in place of the registration form. Names the
    /// alternative that actually exists today rather than only advertising
    /// the upgrade — export is a real backup route, not a consolation prize.
    private var cloudUpsellCard: some View {
        Card(floating: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Recover On A New Phone")
                Text("Registering an email so you can recover your games on a new phone is part of the 3 Leagues plan and above.")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
                Text("On your current plan, back up a game with Export for Transfer from its menu, then import it on the new phone.")
                    .font(.caption)
                    .foregroundStyle(V2Theme.textSecondary)
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
    private var gamesCard: some View {
        if let loadError = syncModel.loadError {
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Your Games")
                    Text(loadError).foregroundStyle(V2Theme.textSecondary)
                    Button("Try Again") { Task { await syncModel.load(context: context) } }
                        .foregroundStyle(V2Theme.accent)
                }
            }
        } else if syncModel.isLoading {
            Color.clear.frame(height: 200)
        } else if !syncModel.games.isEmpty {
            Card(floating: true) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Your Games")
                    ForEach(syncModel.games) { game in
                        gameRow(game)
                    }
                    Text("Pick a game to bring it to this device. You can come back later for the rest.")
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func gameRow(_ game: RemoteGameSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.gameName?.isEmpty == false ? game.gameName! : AppString("Untitled Game"))
                        .foregroundStyle(V2Theme.textPrimary)
                    Text("\(game.mode.capitalized) · Round \(game.roundNumber)")
                        .font(.footnote)
                        .foregroundStyle(V2Theme.textSecondary)
                }
                Spacer()
                gameTrailingControl(for: game)
            }
            if let message = syncModel.errorsByToken[game.gameToken] {
                Text(message).font(.caption).foregroundStyle(V2Theme.danger)
            }
        }
    }

    @ViewBuilder
    private func gameTrailingControl(for game: RemoteGameSummary) -> some View {
        if syncModel.isLocal(game) {
            Label("On This Device", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(V2Theme.accent)
        } else if syncModel.syncingTokens.contains(game.gameToken) {
            ProgressView()
        } else {
            Button("Sync") { syncModel.sync(game, context: context) }
                .buttonStyle(.bordered)
                .tint(V2Theme.accent)
        }
    }
}
