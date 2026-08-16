import SwiftUI

/// Recovers an existing manager identity on a new/lost-phone device via
/// email + OTP (see `AccountClient.linkDeviceRequest`/`linkDeviceVerify`),
/// then hands off to `GameSyncPickerView` to pull individual games down.
/// Presented from `ManagerOnboardingView` before the name prompt and before
/// anything touches `ManagerToken.current` — linking has to adopt the
/// recovered token first, or the lazy-generate path in `ManagerToken.current`
/// would mint and persist a throwaway UUID ahead of it.
struct LinkDeviceView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case enterEmail
        case enterCode(email: String)
        case picker
    }

    @State private var step: Step = .enterEmail
    @State private var emailDraft = ""
    @State private var otpDraft = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showTransferConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .enterEmail: emailForm
                case .enterCode(let email): codeForm(email: email)
                case .picker: GameSyncPickerView(onFinished: { dismiss() })
                }
            }
            .navigationTitle("Link Existing Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .alert("Couldn't Link Device", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Make This Your Active Device?", isPresented: $showTransferConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Link Device") {
                if case .enterCode(let email) = step {
                    Task { await verifyAndLink(email: email) }
                }
            }
        } message: {
            Text("This phone will become the active device for this account. Your other device will stop working until it's linked again.")
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
            } footer: {
                Text("Enter the email you registered on your previous device.")
            }
            Section {
                Button {
                    Task { await sendCode() }
                } label: {
                    if isBusy { ProgressView() } else { Text("Send Code") }
                }
                .disabled(isBusy || !isPlausibleEmail(emailDraft))
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
                    showTransferConfirm = true
                } label: {
                    if isBusy { ProgressView() } else { Text("Link This Device") }
                }
                .disabled(isBusy || otpDraft.count != 6)

                Button("Use a Different Email") {
                    step = .enterEmail
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
            try await AccountClient.shared.linkDeviceRequest(email: email)
            step = .enterCode(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adopts the recovered token, then hands off to the picker — the
    /// picker's own load is what actually drives the device's first
    /// App Attest register call (with the adopted token already in place),
    /// so a rejection there (e.g. an expired pending-bind window) surfaces
    /// as that screen's own inline error rather than a separate check here.
    private func verifyAndLink(email: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let managerToken = try await AccountClient.shared.linkDeviceVerify(email: email, otp: otpDraft)
            ManagerToken.adopt(managerToken)
            step = .picker
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
