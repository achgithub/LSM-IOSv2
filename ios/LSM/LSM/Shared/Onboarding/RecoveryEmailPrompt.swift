import Observation
import SwiftUI

/// Decides when to nudge a cloud-entitled manager who hasn't registered a
/// recovery email yet, and owns the flags that keep that nudge from becoming
/// a nag.
///
/// Deliberately not wired into the purchase screens: the first nudge is due
/// the moment `canUseCloud` first resolves true with no email on file, which
/// covers an in-app upgrade *and* the cases a purchase-screen hook would miss
/// (a subscription restored on this device, bought on another one, or simply
/// resolving late because the first launch was offline).
///
/// Never blocks anything — registering is optional at every tier. The
/// "Don't Remind Me Again" flag is permanent and only the manager can set it;
/// nothing here clears it.
@Observable @MainActor
final class RecoveryEmailPrompt {
    static let shared = RecoveryEmailPrompt()

    /// When the nudge was last actually put on screen. Absent means "never
    /// shown", which is what makes the first one due immediately.
    private static let lastPromptedKey = "recoveryEmailLastPromptedAt"
    /// Set only by the manager tapping "Don't Remind Me Again".
    private static let suppressedKey = "recoveryEmailNeverRemind"

    /// Gap between nudges. Long enough that it reads as a reminder rather
    /// than a nag, short enough to land more than once in a season.
    static let reminderInterval: TimeInterval = 30 * 24 * 60 * 60

    var isPresented = false

    private init() {}

    var isSuppressed: Bool { UserDefaults.standard.bool(forKey: Self.suppressedKey) }

    /// Marks the nudge as due if it is. Safe to call on every foreground —
    /// the interval check and `isPresented` guard make repeat calls a no-op.
    ///
    /// `verified` matters as much as `canUseCloud` here: an unresolved tier
    /// reads as `.free`, and nudging on that would mean pestering free users
    /// about a feature they don't have.
    func evaluate(entitlements: Entitlements, linkedEmail: String) {
        guard !isPresented,
              entitlements.verified,
              entitlements.canUseCloud,
              linkedEmail.isEmpty,
              !isSuppressed
        else { return }

        if let last = UserDefaults.standard.object(forKey: Self.lastPromptedKey) as? Date,
           Date().timeIntervalSince(last) < Self.reminderInterval {
            return
        }
        // Only marks it due — the clock starts in `markShown`, not here. The
        // roots can still refuse to present (onboarding, reauth or a forced
        // downgrade is up), and stamping here would silently burn the nudge
        // for 30 days on a sheet nobody ever saw.
        isPresented = true
    }

    /// Called when the sheet actually reaches the screen. Stamped on
    /// appearance rather than dismissal so closing it by any route
    /// (swipe-down included) still starts the clock.
    func markShown() {
        UserDefaults.standard.set(Date(), forKey: Self.lastPromptedKey)
    }

    func suppress() {
        UserDefaults.standard.set(true, forKey: Self.suppressedKey)
        isPresented = false
    }
}

/// The nudge itself: explains why a recovery email is worth having and takes
/// the registration inline, so it can be finished where it's asked rather
/// than sending the manager off to find Settings.
///
/// Carries its own copy of the email/OTP state machine (as both Profile
/// screens do) instead of sharing one — the three surfaces have different
/// layouts and lifetimes, and a shared model would couple V1's `Form` and
/// V2's `Card` restyle to this sheet's dismissal for no real gain.
struct RecoveryEmailPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""

    @State private var emailDraft = ""
    @State private var otpDraft = ""
    @State private var stage: Stage = .enterEmail
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum Stage {
        case enterEmail
        case enterCode(email: String)
        case done
    }

    private var trimmedEmail: String {
        emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isPlausibleEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".") && value.count > 4
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .enterEmail: emailForm
                case .enterCode(let email): codeForm(email: email)
                case .done: doneForm
                }
            }
            .scrollContentBackground(.hidden)
            .background(V2Theme.background.ignoresSafeArea())
            .navigationTitle("Secure Your Games")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { RecoveryEmailPrompt.shared.markShown() }
            .toolbarBackground(V2Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
        .alert("Couldn't Complete That", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var emailForm: some View {
        Form {
            Section {
                Text("Your plan includes getting your games back on a new phone. Register an email now and you'll be able to recover them if this one is ever lost, stolen or replaced.")
                    .font(.subheadline)
            }
            Section {
                TextField("Email", text: $emailDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
            } header: {
                Text("Email")
            } footer: {
                Text("Only used to recover your games. We won't email you about anything else.")
            }
            Section {
                Button {
                    Task { await sendCode() }
                } label: {
                    if isBusy { ProgressView() } else { Text("Send Code") }
                }
                .disabled(isBusy || !isPlausibleEmail(trimmedEmail))
            }
            Section {
                // Permanent opt-out, kept visually quiet and last — the
                // default answer we want is "not now", which the toolbar
                // already offers without spending the opt-out.
                Button("Don't Remind Me Again", role: .destructive) {
                    RecoveryEmailPrompt.shared.suppress()
                    dismiss()
                }
            } footer: {
                Text("You can still register an email any time from Settings → Profile.")
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
                    Task { await verifyCode(email: email) }
                } label: {
                    if isBusy { ProgressView() } else { Text("Verify") }
                }
                .disabled(isBusy || otpDraft.count != 6)

                Button("Use a Different Email") {
                    stage = .enterEmail
                    otpDraft = ""
                }
            }
        }
    }

    @ViewBuilder
    private var doneForm: some View {
        Form {
            Section {
                Label("Email registered", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(V2Theme.accent)
                Text("If you get a new phone, enter \(linkedEmail) during setup to get your games back.")
                    .font(.subheadline)
            }
            Section {
                Button("Done") { dismiss() }
            }
        }
    }

    private func sendCode() async {
        let email = trimmedEmail
        guard isPlausibleEmail(email) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AccountClient.shared.registerRequest(email: email)
            stage = .enterCode(email: email)
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
            stage = .done
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
