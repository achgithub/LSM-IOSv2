#!/usr/bin/env python3
"""Fails if a user-facing literal isn't translated.

A missing translation compiles cleanly and renders English, so the build can't
catch this — that's what let most of V2 ship untranslated. This walks the
literals passed to `LocalizedStringKey` parameters and asserts each one is a
key in `LSM/Localizable.xcstrings`.

Run from ios/LSM:   python3 scripts/check-localization.py

Adding a string? Put it in gen_catalog.py, re-run `python3 gen_catalog.py`,
and commit the regenerated catalog with your code (see CLAUDE.md).
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "LSM" / "Localizable.xcstrings"

# Parameters typed `LocalizedStringKey`, so a literal here goes to the catalog.
# User data goes through each component's `verbatim:` initializer instead and
# is deliberately not matched.
PARAMS = re.compile(
    r"(?:SectionHeader\(title:|PrimaryButton\(title:|ActionRow\(\s*\n?\s*title:"
    r"|SelectablePill\(title:|MicroLabel\(text:|V2StatusBadge\(label:"
    r"|\.v2FloatingHeader\(|\.v2FloatingHeaderWithTiles\(|actionTitle:)"
    r'\s*"((?:[^"\\]|\\.)+)"'
)

# `\(someCount)` becomes %lld in the key, everything else %@.
INT_HINTS = ("count", "roundNumber", "nextRoundNumber", "submitted", "eligible",
             "requiredCount", "md", "unpickedCount", "notStartedCount", "Number")
INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")

# Symbols, pure data and dev-only strings fall back to the source string by
# design (see gen_catalog.py's docstring).
SKIP = {" ", "A–Z", "Last Stand Manager",
        "Check StoreKit Products (bypass RevenueCat)"}


def catalog_key(literal: str) -> str:
    return INTERP.sub(
        lambda m: "%lld" if any(h in m.group(0) for h in INT_HINTS) else "%@",
        literal,
    )


def main() -> int:
    keys = set(json.loads(CATALOG.read_text())["strings"])
    missing: dict[str, str] = {}
    for path in sorted((ROOT / "LSM").rglob("*.swift")):
        for match in PARAMS.finditer(path.read_text()):
            key = catalog_key(match.group(1))
            if key not in keys and key not in SKIP:
                missing.setdefault(key, str(path.relative_to(ROOT)))

    if missing:
        print(f"{len(missing)} untranslated string(s) — add to gen_catalog.py:\n")
        for key, where in sorted(missing.items()):
            print(f"  {key!r}\n      first seen in {where}")
        return 1

    print(f"All localizable literals present in the catalog ({len(keys)} keys).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
