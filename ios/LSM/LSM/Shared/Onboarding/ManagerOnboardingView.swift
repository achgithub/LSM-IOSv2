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

/// First-launch prompt for the manager's name, and — for a returning
/// subscriber — the way back to their games.
///
/// No email *registration* here any more: registering is what creates the
/// account link, and it's a cloud feature (`leagues_3` and above, see
/// `Entitlements.canUseCloud`), so it belongs at the moment that's actually
/// true — Settings → Profile, or `RecoveryEmailPrompt`. At first launch you
/// are in one of two situations and neither of them is "register": either an
/// account already exists (recover it — link-device) or you haven't
/// subscribed yet (nothing to secure).
///
/// The branch is possible because a subscription lives on the Apple ID, not
/// the phone: on a fresh install RevenueCat picks the active one up on its
/// own, and `AppBootstrap` awaits that behind the 2.5s splash — so by the
/// time this draws, `Entitlements` usually already knows. When it doesn't
/// (offline, a slow or failed refresh) this falls back to the plain
/// name-only form, which is why "I Already Have an Account" stays visible
/// there too: it's the escape hatch for a subscriber we failed to recognise.
///
/// Linking is never gated, at any tier. You can only link to an account that
/// already exists, and accounts are only ever created by someone entitled at
/// the time — so it gates itself, and a paying manager can never be locked
/// out of their own games by a tier that hasn't resolved yet.
struct ManagerOnboardingView: View {
    @Binding var managerName: String
    /// Read directly off the singleton rather than `@Environment` — this is
    /// presented as a sheet from two different roots, and depending on each
    /// one's environment plumbing to reach it is a silent-failure risk for
    /// the branch below.
    @State private var entitlements = Entitlements.shared

    @State private var nameDraft = ""
    @State private var showLinkDevice = false

    private var trimmedName: String { nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canContinue: Bool { !trimmedName.isEmpty }

    /// A live cloud subscription on this Apple ID with no games on this
    /// device yet — almost always a new/replacement phone. `verified` is
    /// required because an unresolved tier reads as `.free`.
    private var isReturningSubscriber: Bool {
        entitlements.verified && entitlements.canUseCloud
    }

    var body: some View {
        NavigationStack {
            form
                .scrollContentBackground(.hidden)
                .background(V2Theme.background.ignoresSafeArea())
                .navigationTitle(isReturningSubscriber ? "Welcome Back" : "Welcome")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(V2Theme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showLinkDevice) {
            LinkDeviceView()
        }
    }

    @ViewBuilder
    private var form: some View {
        Form {
            if isReturningSubscriber {
                // Promoted above the name field, unlike the free path: for
                // someone who just replaced a phone, recovering their games
                // *is* the task, and the name they're about to type is one
                // link-device will overwrite anyway.
                Section {
                    Text("Your \(entitlements.tier.label) subscription is active on this Apple ID. If you had games on another phone, bring them over here.")
                        .font(.subheadline)
                    Button("Get My Games Back") { showLinkDevice = true }
                        .fontWeight(.semibold)
                } header: {
                    Text("Recover your games")
                }
            }

            Section {
                // Single localized string key — can't wrap without changing the key.
                // swiftlint:disable:next line_length
                Text("What's your name? You'll be added to games you create, and your pick is always shown on shared summary cards — even in anonymous mode — so it's fair on the other players.")
                    .font(.subheadline)
            } header: {
                Text(isReturningSubscriber ? "Or start fresh" : "")
            }
            Section("Your name") {
                TextField("e.g. Andy", text: $nameDraft)
                    .textInputAutocapitalization(.words)
            }

            if !isReturningSubscriber {
                Section {
                    // Deliberately below the name field, not above — this is
                    // the exception case (new/lost phone), not the default
                    // first-launch path. Presented before anything here
                    // touches ManagerToken.current — see LinkDeviceView's
                    // header comment for why that ordering matters.
                    Button("I Already Have an Account") { showLinkDevice = true }
                } footer: {
                    Text("Recovering games from a phone you no longer have? Start here.")
                }
            }

            Section {
                Button("Continue") { managerName = trimmedName }
                    .disabled(!canContinue)
            }
        }
    }
}
