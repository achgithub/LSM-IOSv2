import SwiftUI

/// Card restyle of `AccountSettingsView` — same logic (register email → OTP
/// → linked), copied rather than shared, matching this branch's precedent.
/// Deliberately not a "backup" screen: nothing about any game is touched
/// here, only the email↔manager_token link — see `AccountClient`.
struct AccountSettingsViewV2: View {
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
        ScrollView {
            LazyVStack(spacing: V2Theme.Spacing.section) {
                if linkedEmail.isEmpty {
                    registrationCard
                } else {
                    linkedCard
                }
            }
            .padding(.horizontal, V2Theme.Spacing.horizontal)
            .padding(.vertical, V2Theme.Spacing.section)
        }
        .background(V2Theme.background.ignoresSafeArea())
        .v2Header("Account")
        .alert("Couldn't Complete That", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var linkedCard: some View {
        VStack(spacing: V2Theme.Spacing.section) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Registered Email")
                    HStack {
                        Text(linkedEmail)
                            .font(V2Theme.Typography.rowTitle)
                            .foregroundStyle(V2Theme.textPrimary)
                        Spacer()
                    }
                    Text("If you get a new phone, enter this email during setup to recover your games.")
                        .font(.caption)
                        .foregroundStyle(V2Theme.textSecondary)
                }
            }
            Button("Use a Different Email", role: .destructive) {
                linkedEmail = ""
                stage = .enterEmail
                emailDraft = ""
                otpDraft = ""
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var registrationCard: some View {
        switch stage {
        case .enterEmail:
            VStack(spacing: V2Theme.Spacing.section) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Register Your Email")
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
                Card {
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
                    stage = .enterEmail
                    otpDraft = ""
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(V2Theme.accent)
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
