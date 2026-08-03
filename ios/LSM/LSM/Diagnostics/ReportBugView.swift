import SwiftUI
import MessageUI
import UIKit

/// Sends the recent diagnostic log (see `DiagnosticLog`) to the developer,
/// pre-addressed via Mail when available, falling back to the same
/// `ActivityShareView` share sheet the CSV export uses when it isn't (no
/// Mail account configured on-device).
struct ReportBugView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var whatHappened = ""
    @State private var isPreparing = false
    @State private var reportFile: URL?
    @State private var showingMailComposer = false
    @State private var showingShareFallback = false
    @State private var prepareError: String?

    private static let supportEmail = "sportsmanager@zohomail.eu"

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Text("Ran into something wrong? Describe what happened below and send it to the developer — the recent diagnostic log (what the app was doing right before) gets attached automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("What happened?") {
                TextEditor(text: $whatHappened)
                    .frame(minHeight: 120)
            }
            Section {
                Button {
                    Task { await prepareAndSend() }
                } label: {
                    if isPreparing {
                        ProgressView()
                    } else {
                        Label("Send Report", systemImage: "ladybug.fill")
                    }
                }
                .disabled(isPreparing)
            } footer: {
                Text("Includes: app version \(appVersion), device/iOS info, current plan, and the recent diagnostic log. No personal data beyond what you type above.")
            }
        }
        .navigationTitle("Report a Bug")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMailComposer) {
            if let reportFile {
                MailComposeView(
                    recipient: Self.supportEmail,
                    subject: "LSM Bug Report — \(appVersion)",
                    body: whatHappened.isEmpty ? "(no description entered)" : whatHappened,
                    attachmentURL: reportFile,
                    onFinish: { dismiss() }
                )
            }
        }
        .sheet(isPresented: $showingShareFallback) {
            if let reportFile {
                ActivityShareView(items: [reportFile])
            }
        }
        .alert("Couldn't Prepare Report", isPresented: Binding(
            get: { prepareError != nil },
            set: { if !$0 { prepareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(prepareError ?? "")
        }
    }

    private func prepareAndSend() async {
        isPreparing = true
        defer { isPreparing = false }
        let log = await DiagnosticLog.shared.recentText()
        let device = UIDevice.current
        let header = """
        LSM Bug Report
        App version: \(appVersion)
        Device: \(device.model), iOS \(device.systemVersion)
        Plan: \(entitlements.tier.label)
        Description:
        \(whatHappened.isEmpty ? "(none entered)" : whatHappened)

        --- Recent diagnostic log ---
        \(log)
        """
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LSM Bug Report.txt")
            try header.write(to: url, atomically: true, encoding: .utf8)
            reportFile = url
            if MFMailComposeViewController.canSendMail() {
                showingMailComposer = true
            } else {
                showingShareFallback = true
            }
        } catch {
            prepareError = "Couldn't prepare the report. Please try again."
        }
    }
}
