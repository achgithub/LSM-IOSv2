import Observation
import SwiftUI

/// Set by `AppAttestService` when this device's key has died and the account
/// it was linked to needs fresh proof via email (see `AttestError.deviceLockedOut`).
/// Observed by `RootTabView` to present `ReauthorizeDeviceView` automatically —
/// the first network call anywhere in the app after a key loss trips this,
/// rather than waiting for the user to stumble into Settings.
@Observable @MainActor
final class DeviceLockoutState {
    static let shared = DeviceLockoutState()

    private(set) var isLockedOut = false

    private init() {}

    func markLockedOut() { isLockedOut = true }
    func clear() { isLockedOut = false }
}

/// The app owner's identity, stored in user defaults. Used to add "you" to games
/// you create and to flag your pick on shared summaries (spec §13b.2).
enum ManagerSettings {
    static let nameKey = "managerName"
}

/// Locally-cached email shown once registered — display convenience only,
/// not a security boundary. The server (`accounts` table) is the source of
/// truth; this just avoids re-asking "what did I register?" on every visit.
enum AccountSettings {
    static let linkedEmailKey = "linkedAccountEmail"
}

/// First-launch prompt for the manager's name, plus an optional email —
/// email is free for every tier (see `AccountClient`) and captured here,
/// not gated behind Settings, because Settings is only reachable *after*
/// you already have a working phone. The whole point of registering is
/// recovering from the phone you're using right now no longer being an
/// option — asking later, only to people who've already subscribed, misses
/// exactly the people who'll actually need it.
struct ManagerOnboardingView: View {
    @Binding var managerName: String
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""

    @State private var nameDraft = ""
    @State private var emailDraft = ""
    @State private var otpDraft = ""
    @State private var stage: Stage = .nameAndEmail
    @State private var showLinkDevice = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum Stage {
        case nameAndEmail
        case enterCode(email: String)
    }

    private var trimmedName: String { nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var emailIsPlausible: Bool { trimmedEmail.contains("@") && trimmedEmail.contains(".") && trimmedEmail.count > 4 }
    private var canContinue: Bool { !trimmedName.isEmpty && (trimmedEmail.isEmpty || emailIsPlausible) }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .nameAndEmail: nameAndEmailForm
                case .enterCode(let email): codeForm(email: email)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showLinkDevice) {
            LinkDeviceView()
        }
        .alert("Couldn't Send Code", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var nameAndEmailForm: some View {
        Form {
            Section {
                // Single localized string key — can't wrap without changing the key.
                // swiftlint:disable:next line_length
                Text("What's your name? You'll be added to games you create, and your pick is always shown on shared summary cards — even in anonymous mode — so it's fair on the other players.")
                    .font(.subheadline)
            }
            Section("Your name") {
                TextField("e.g. Andy", text: $nameDraft)
                    .textInputAutocapitalization(.words)
            }
            Section {
                TextField("Email", text: $emailDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
            } header: {
                Text("Email (optional)")
            } footer: {
                Text("So you can get your games back if you ever lose this phone. Not needed otherwise.")
            }
            Section {
                // Deliberately below the name/email fields, not above — this
                // is the exception case (new/lost phone), not the default
                // first-launch path. Presented before anything here touches
                // ManagerToken.current — see LinkDeviceView's header comment
                // for why that ordering matters.
                Button("I Already Have an Account") { showLinkDevice = true }
            }
            Section {
                Button {
                    Task { await proceed() }
                } label: {
                    if isBusy { ProgressView() } else { Text("Continue") }
                }
                .disabled(!canContinue || isBusy)
            }
        }
    }

    @ViewBuilder
    private func codeForm(email: String) -> some View {
        Form {
            Section {
                LabeledContent("Email", value: email)
                TextField("6-digit code", text: $otpDraft)
                    .keyboardType(.numberPad)
            } footer: {
                Text("Enter the code we just sent to \(email).")
            }
            Section {
                Button {
                    Task { await verifyAndFinish(email: email) }
                } label: {
                    if isBusy { ProgressView() } else { Text("Verify") }
                }
                .disabled(isBusy || otpDraft.count != 6)

                Button("Skip for Now") { managerName = trimmedName }
            }
        }
    }

    /// Saves the name immediately either way. Only moves to the code step if
    /// an email was actually entered — leaving it blank finishes onboarding
    /// right here, since email is genuinely optional.
    private func proceed() async {
        guard canContinue else { return }
        guard !trimmedEmail.isEmpty else {
            managerName = trimmedName
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AccountClient.shared.registerRequest(email: trimmedEmail)
            stage = .enterCode(email: trimmedEmail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyAndFinish(email: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AccountClient.shared.registerVerify(email: email, otp: otpDraft)
            linkedEmail = email
            managerName = trimmedName
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
