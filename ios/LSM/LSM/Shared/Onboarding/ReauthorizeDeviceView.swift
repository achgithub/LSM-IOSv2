import SwiftUI

/// Presented automatically (via `DeviceLockoutState`) when this exact device's
/// App Attest key has died and the account it was linked to needs fresh proof
/// via email — see `AttestError.deviceLockedOut` and worker-api's
/// account-transfer guard in routes/attest.ts.
///
/// Unlike `LinkDeviceView` (a genuinely new/lost phone recovering a manager
/// identity it doesn't have yet), this is the *same* manager_token asking to
/// become its own account's active device again — so the email is already
/// known (`AccountSettings.linkedEmailKey`), there's nothing to adopt, and on
/// success this hands straight back to `AppAttestService` to consume the
/// pending-bind window rather than to `GameSyncPickerView`.
struct ReauthorizeDeviceView: View {
    @AppStorage(AccountSettings.linkedEmailKey) private var linkedEmail = ""

    @State private var otpDraft = ""
    @State private var isBusy = false
    @State private var codeSent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Email", value: linkedEmail)
                    TextField("6-digit code", text: $otpDraft)
                        .keyboardType(.numberPad)
                } footer: {
                    Text(codeSent
                         ? "This phone lost its security key. Enter the code we just sent to \(linkedEmail) to reconnect it."
                         : "This phone lost its security key. Sending a code to \(linkedEmail)…")
                }
                Section {
                    Button {
                        Task { await verify() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Reconnect This Device") }
                    }
                    .disabled(isBusy || !codeSent || otpDraft.count != 6)
                }
            }
            .navigationTitle("Confirm It's You")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .task { await sendCode() }
        .alert("Couldn't Reconnect", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func sendCode() async {
        guard !linkedEmail.isEmpty, !codeSent else { return }
        do {
            try await AccountClient.shared.linkDeviceRequest(email: linkedEmail)
            codeSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify() async {
        isBusy = true
        defer { isBusy = false }
        do {
            // Same manager_token this device already has — opens the
            // pending-bind window rather than something to adopt.
            _ = try await AccountClient.shared.linkDeviceVerify(email: linkedEmail, otp: otpDraft)
            try await AppAttestService.shared.completeReauthorization()
            await DeviceLockoutState.shared.clear()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
