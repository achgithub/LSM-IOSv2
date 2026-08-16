import SwiftUI

/// The app owner's identity, stored in user defaults. Used to add "you" to games
/// you create and to flag your pick on shared summaries (spec §13b.2).
enum ManagerSettings {
    static let nameKey = "managerName"
}

/// First-launch prompt for the manager's name (shown until a name is set).
struct ManagerOnboardingView: View {
    @Binding var managerName: String
    @State private var draft = ""
    @State private var showLinkDevice = false

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Single localized string key — can't wrap without changing the key.
                    // swiftlint:disable:next line_length
                    Text("What's your name? You'll be added to games you create, and your pick is always shown on shared summary cards — even in anonymous mode — so it's fair on the other players.")
                        .font(.subheadline)
                }
                Section("Your name") {
                    TextField("e.g. Andy", text: $draft)
                        .textInputAutocapitalization(.words)
                        .onSubmit(save)
                }
                Section {
                    // Deliberately below the name field, not above — this is
                    // the exception case (new/lost phone), not the default
                    // first-launch path. Presented before anything here
                    // touches ManagerToken.current — see LinkDeviceView's
                    // header comment for why that ordering matters.
                    Button("I Already Have an Account") { showLinkDevice = true }
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: save).disabled(trimmed.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showLinkDevice) {
            LinkDeviceView()
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        managerName = trimmed
    }
}
