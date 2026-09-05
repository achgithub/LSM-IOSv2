# Review checklist

- [ ] Traced every computed `var` in touched SwiftUI views for per-render cost (loops/parsing over collections); cached anything expensive in `@State` invalidated only on its real trigger — checked against full-season data, not demo data.

- [ ] **Every new user-facing string is translated in the same change.** The app ships in en/es/de/fr/nl/it and that is not optional or deferrable — a string added without translations is an incomplete change, not a follow-up ticket. Add it to `gen_catalog.py`, re-run `python3 gen_catalog.py`, and commit the regenerated `LSM/Localizable.xcstrings` alongside the code.

## Localization: the trap that hides missing translations

A missing translation **compiles cleanly and renders English**, so a green build proves nothing. Two ways a string silently escapes the catalog:

1. **`Text(someString)` renders verbatim.** Only `Text("literal")` and `LocalizedStringKey`-typed params go through the catalog. A `String`-typed label parameter never localizes, however it's called.
2. **Interpolation changes the key.** `Text("Sent to \(email).")` looks up `"Sent to %@."`, not the source text. `\(someInt)` becomes `%lld`. Put the `%@`/`%lld` form in `gen_catalog.py`, and confirm the real key by reading `Localizable.xcstrings` rather than assuming.

Design-system components take `LocalizedStringKey` so literals localize automatically. When a label is genuinely user data (a game name, a player name), use the `verbatim:` initializer — the compiler will not let a `String` bind to the localized parameter, so this is always a deliberate choice, never an accident.

To verify a change, don't eyeball it — run the guard, which fails on any localizable literal missing from the catalog:

```
python3 scripts/check-localization.py
```
