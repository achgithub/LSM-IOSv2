import SwiftUI

/// Locally-cached email shown in Settings after a successful registration —
/// display convenience only, not a security boundary. The server (accounts
/// table) is the source of truth; this just avoids re-asking "what did I
/// register?" on every visit to this screen.
enum AccountSettings {
    static let linkedEmailKey = "linkedAccountEmail"
}

/// Registers an email for later device recovery — see AccountClient's header
/// comment. Deliberately not a "backup" screen: nothing about any game is
/// touched here, only the email↔manager_token link.
struct AccountSettingsView: View {
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""

    @State private var emailDraft = ""
    @State private var otpDraft = ""
    @State private var stage: Stage = .enterEmail
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum Stage {
        case enterEmail
        case enterCode(email: String)
    }

    var body: some View {
        Form {
            if linkedEmail.isEmpty {
                registrationSection
            } else {
                Section {
                    LabeledContent("Registered email", value: linkedEmail)
                } footer: {
                    Text("If you get a new phone, enter this email during setup to recover your games.")
                }
                Section {
                    Button("Use a Different Email", role: .destructive) {
                        linkedEmail = ""
                        stage = .enterEmail
                        emailDraft = ""
                        otpDraft = ""
                    }
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
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
    private var registrationSection: some View {
        switch stage {
        case .enterEmail:
            Section {
                TextField("Email", text: $emailDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
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
                    stage = .enterEmail
                    otpDraft = ""
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
            stage = .enterEmail
            emailDraft = ""
            otpDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
