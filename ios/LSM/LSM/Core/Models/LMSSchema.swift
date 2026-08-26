import SwiftData

/// Versioned schema scaffold, introduced after a data-loss incident: the app
/// previously built its `ModelContainer` via the bare `.modelContainer(for:)`
/// convenience modifier with no `SchemaMigrationPlan`. That modifier has no
/// way to refuse or surface a failed/unsafe migration — when a stale
/// (older-schema) build was installed over a simulator store a newer build
/// had already written to, SwiftData silently recreated an empty store
/// instead of failing loudly, and the example games in it were gone with no
/// crash, log, or error anywhere in this codebase to explain why.
///
/// `V1` is a snapshot of the schema as it already existed at the time of
/// this fix (same models/fields `LSMApp` already listed), not the app's
/// actual original schema — this schema was never versioned before now.
/// SwiftData matches an on-disk store to a `VersionedSchema` by structure,
/// not by this type merely existing, so introducing V1 here as an exact
/// match of the live shape is safe for existing installs: nothing migrates,
/// it just gives the current shape an explicit, checkable identity.
///
/// From this point forward: a purely additive change (a new defaulted
/// property, a new relationship, a whole new model type) is still safe to
/// make in place, matching what SwiftData's automatic lightweight migration
/// already handled fine for this app's last few model changes. Anything
/// else — a rename, a type change, a removal, or splitting/merging models —
/// needs a new `LMSSchemaV2` (copy this enum, bump `versionIdentifier`) plus
/// a `MigrationStage` added to `LMSMigrationPlan.stages` below, so the
/// transition is explicit and testable instead of hoping the automatic path
/// covers it.
enum LMSSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Game.self, Player.self, Round.self, Pick.self, Prediction.self,
            KillerPlayerState.self, KillerPrediction.self, RosterMember.self, PlayerGroup.self,
        ]
    }
}

/// Currently just the V1 baseline with no migration stages — see
/// `LMSSchemaV1`'s doc comment for what triggers adding a V2 here.
enum LMSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LMSSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
