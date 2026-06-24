# LSM app source layout (v2)

One Swift target (`LSM`), so folders are organisational only — every file is in
the same module and types resolve across folders regardless of location. The
project uses Xcode **file-system synchronized groups**: anything added under this
tree is auto-included in the target, no `.xcodeproj` edits needed.

```
LSM/
├─ App/            App entry (LSMApp @main) + root views (AppRootView, RootTabView)
├─ Core/           Shared foundations used by both modes
│  ├─ Engine/      Pure, persistence-free game logic (carried over from v1 as-is)
│  ├─ Models/      Game / Player / Round / Pick / roster (+ Enums)
│  ├─ DesignSystem/
│  └─ Localization/
├─ Modes/          The two game modes that share Core + Cloud
│  ├─ GameMode.swift   The .lms | .predictor discriminator
│  ├─ LMS/         Last Man Standing — elimination gameplay (ported from v1):
│  │               Games, Rounds, Summary, Demo
│  └─ Predictor/   Season-long score prediction (NEW in v2) — skeleton
├─ Cloud/          D1-backed data layer (was v1's read-only Networking):
│                  APIClient/LeagueData (sports data) + GameCloudClient (new game state)
├─ Submissions/    Manager's approve/reject queue for anonymous PWA submissions (NEW)
├─ Shared/         Cross-mode chrome + league-data views:
│                  Onboarding, Settings, Splash, Players, Matches, Standings
├─ Monetization/   RevenueCat + AdMob (shared, carried over)
├─ Config/         Enabled leagues / league list (shared)
├─ Resources/      leagues.json, fonts, Localizable.xcstrings
└─ Assets.xcassets/
```

## Notes / open to adjust

- The split of existing v1 features between `Modes/LMS/` and `Shared/` is a
  first pass. `Players`, `Matches`, `Standings` sit in `Shared/` because both
  modes reuse them; the elimination-specific flows (`Games`, `Rounds`, `Summary`,
  `Demo`) are under `Modes/LMS/`. Easy to re-slice — moving files between folders
  has no build impact.
- `Cloud/` keeps v1's read-only sports-data client untouched and adds
  `GameCloudClient` (stub) for v2's per-game/per-player Worker routes.
- `Modes/Predictor/`, `Submissions/`, and `GameCloudClient` are skeletons —
  placeholders that make the structure real; gameplay/networking not built yet.
