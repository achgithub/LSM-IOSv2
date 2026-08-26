import SwiftUI

/// Presented automatically (via `DeviceLockoutState`) when this exact device's
/// App Attest key has died and the account it was linked to needs fresh proof
/// via email — see `AttestError.deviceLockedOut` and worker-api's
/// account-transfer guard in routes/attest.ts.
///
/// Unlike `LinkDeviceView` (a genuinely new/lost phone recovering a manager
/// identity it doesn't have yet), this is the *same* manager_token asking to
/// become its own account's active device again — there's nothing to adopt,
/// and on success this hands straight back to `AppAttestService` to consume
/// the pending-bind window rather than to `GameSyncPickerView`.
///
/// The email is usually already known (`AccountSettings.linkedEmailKey`), but
/// isn't guaranteed to be: the server can have committed the account link
/// (upsertAccount + linkAccount in /account/verify) while this device's local
/// cache of that success never got written — an interrupted response, or an
/// earlier reinstall that cleared UserDefaults without touching the server.
/// So this asks for the email whenever the local cache is empty, same as
/// LinkDeviceView's recovery step, rather than assuming it's always known.
struct ReauthorizeDeviceView: View {
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""

    private enum Step {
        case enterEmail
        case enterCode(email: String)
    }

    @State private var step: Step = .enterEmail
    @State private var emailDraft = ""
    @State private var otpDraft = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .enterEmail: emailForm
                case .enterCode(let email): codeForm(email: email)
                }
            }
            .scrollContentBackground(.hidden)
            .background(V2Theme.background.ignoresSafeArea())
            .navigationTitle("Confirm It's You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(V2Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .interactiveDismissDisabled()
        .task {
            if !linkedEmail.isEmpty { await sendCode(email: linkedEmail) }
        }
        .alert("Couldn't Reconnect", isPresented: Binding(
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
                TextField("Email", text: $emailDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
            } header: {
                Text("This phone lost its security key")
            } footer: {
                Text("Enter the email you registered on this account to reconnect this device.")
            }
            Section {
                Button {
                    Task { await sendCode(email: normalizedEmail) }
                } label: {
                    if isBusy { ProgressView() } else { Text("Send Code") }
                }
                .disabled(isBusy || !isPlausibleEmail(normalizedEmail))
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
                    Task { await verify(email: email) }
                } label: {
                    if isBusy { ProgressView() } else { Text("Reconnect This Device") }
                }
                .disabled(isBusy || otpDraft.count != 6)

                Button("Use a Different Email") {
                    step = .enterEmail
                    otpDraft = ""
                }
            }
        }
    }

    private var normalizedEmail: String {
        emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isPlausibleEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".") && value.count > 4
    }

    private func sendCode(email: String) async {
        guard isPlausibleEmail(email) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AccountClient.shared.linkDeviceRequest(email: email)
            step = .enterCode(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify(email: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            // Same manager_token this device already has — opens the
            // pending-bind window rather than something to adopt.
            _ = try await AccountClient.shared.linkDeviceVerify(email: email, otp: otpDraft)
            try await AppAttestService.shared.completeReauthorization()
            linkedEmail = email
            await DeviceLockoutState.shared.clear()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
