//
//  LSMApp.swift
//  LSM
//

import SwiftUI
import SwiftData
import OSLog

private let modelContainerLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lsm", category: "modelContainer")

@main
struct LSMApp: App {
    let container = LSMApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(container)
    }

    /// Builds the shared `ModelContainer` against `LMSSchemaV1`/
    /// `LMSMigrationPlan` (see that file's doc comment for why) instead of
    /// the bare `.modelContainer(for:)` convenience this used to call
    /// directly — that convenience has no way to refuse a failed/unsafe
    /// migration, so a schema mismatch silently recreates an empty store
    /// instead of failing loudly. Crashing here is deliberate: a manager's
    /// games disappearing with no error anywhere is worse than a crash that
    /// actually gets reported and investigated.
    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: LMSSchemaV1.self),
                migrationPlan: LMSMigrationPlan.self
            )
        } catch {
            modelContainerLog.fault("ModelContainer failed to load — refusing to silently recreate an empty store: \(String(describing: error), privacy: .public)")
            fatalError("ModelContainer failed to load: \(error)")
        }
    }
}
