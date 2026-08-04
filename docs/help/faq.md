# FAQ

> **Placeholder — v1 → V2 transition.** The app is mid-redesign: some
> managers will see the original (v1) screens, others the new card-based
> V2 screens (toggled on in Settings). The questions below apply either
> way — they're about how the app behaves, not which screens you're
> looking at. Once V2 fully replaces v1, revisit this doc and add
> screenshots for each answer.
>
> Not currently linked anywhere in the app (same as `refresh-policy.md`
> in this folder) — this is a staging doc for now.

---

## Sharing / handing a game to another manager

### I exported a game and imported it on another phone — will the PWA player links still work?

No. Exporting a game (**Export for Transfer**, from the export menu on a
game's detail screen) bundles the game's settings, rounds, and player
names into a file. Importing it on another device creates a **fresh
copy** with new internal IDs — but it deliberately does **not** carry
over the cloud link that PWA player-submission links depend on
(`cloudGameTokenRaw` stays empty on import; see
`Core/Transfer/GameTransfer.swift`).

So:
- Any links players were already using against the **original**
  manager's game stop resolving — the new copy has no cloud game
  behind it yet.
- If the manager who imported the game wants to use PWA links, they
  need to send new ones from their own device (**Resend to Player
  App**, on the game's detail screen) — this mints a brand-new link,
  and players need to switch to it.

This is deliberate, not a bug: importing a game is a **copy**, not a
live handoff of an in-progress cloud session. If a manager needs
players to keep submitting through the *same* running session without
re-sending links, that's a different feature (live game handoff) —
not what Export/Import does today.

### If two players have the same name, what happens on import?

The import flow checks player names against the roster already on the
receiving device. A collision prompts a rename before the import
finishes — the imported game's picks/predictions for that player are
attributed to the new name once resolved. No two players end up merged
into one by accident.

---

## Auto-Assign (Last Man Standing)

### Someone forgot to pick — what does Auto-Assign actually give them?

It assigns the lowest-ranked (bottom-of-table) team from that round's
fixtures that the player hasn't already used, so it's a safe fallback
rather than a title contender. It never assigns a team the player has
used before (unless the game allows repeat picks), and it always finds
something as long as there's at least one eligible team left.

### The season just started and every team is on 0 points — how does "bottom of the table" work then?

Before real results exist, the app can't rank teams by points, so it
falls back to a stable ordering (alphabetical) rather than a
meaningless 0-0-0 table. Once matches are actually played, real league
position takes over.

### A round blends fixtures from more than one league — which league's "bottom" does it use?

Whichever team has the worst raw table position across all the
blended leagues, compared directly (a 20th-place team in a 20-team
league and a 20th-place team in a 24-team league currently count as
equally "bottom", even though the second one is roughly mid-table).
Known limitation, not treated as urgent — flag it if it's causing a
real problem in practice.

---

## Add more entries below as they come up

Format: a short question as a heading, a plain-English answer, and a
one-line pointer to the code/logic it's describing if it's not obvious
from the answer alone.
