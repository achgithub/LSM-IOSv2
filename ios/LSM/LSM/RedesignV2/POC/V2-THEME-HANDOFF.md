# V2 In-App Experience Theme POC

## Purpose

This folder is an isolated visual proof of concept for the V2 iOS experience. It explores a higher-grade, football-stadium presentation across the app rather than only changing colours.

Nothing here is connected to production navigation, `V2Theme`, or the app launch flow. It is intended to be reviewed, refined, and then deliberately translated into the production V2 design system.

## Files

- `V2ExperienceThemePOC.swift` — interactive SwiftUI showroom containing Games, Matchday, Loading, and Winner scenes.
- `Assets/V2POCStadiumDay.png` — the daylight master stadium artwork used by both appearances.
- `Assets/V2POCStadium.png` — an earlier night-first exploration retained only as reference. It is not used by the current POC.

## Agreed visual direction

The experience should feel like being inside a modern football stadium while remaining clear and useful as a game-management app.

- Content is centred so the stadium floodlights frame it instead of overpowering it.
- The stadium supplies atmosphere and depth; cards remain the primary information surface.
- The lower portion includes a subtle green pitch and small goal.
- Game types retain the existing V2 mode identities from `V2Theme.Mode`:
  - Last Man Standing: blue (`#4C9AFF` in dark mode) with rounded typography.
  - Predictor: indigo (`#6366F1` in dark mode) with monospaced typography.
  - Killer: orange-red (`#F2542D` in dark mode) with serif typography.
  - Success: green
  - Winner/reward moments: gold
- Panels use restrained translucency so the environment remains visible without reducing legibility.

## Light mode

Light mode is the master composition and should be designed first.

- Bright blue sky rather than grey or blue-grey.
- Natural green pitch.
- Stadium floodlights are switched off.
- Light cards and dark text maintain accessible contrast.
- Avoid heavy grey overlays or desaturation.

## Dark mode

Dark mode uses the exact same daylight stadium image and geometry. It must not swap to a differently shaped stadium because that makes the appearance transition visually jump.

The dark treatment is produced in SwiftUI by:

- reducing saturation;
- increasing contrast slightly;
- reducing image brightness;
- applying a navy multiply grade;
- adding blue-white lamp illumination and light beams as overlays.

Each floodlight housing has a visible white core and blue-white bloom. The beams should clearly originate from those lamps. This lets the transition feel like evening falling and the stadium lights switching on.

## Background and scrolling behaviour

The stadium is fixed to the viewport; it is outside each screen's `ScrollView`.

For long game lists:

- only cards and page content scroll;
- the stadium never tiles, stretches, or scrolls away;
- floodlights remain anchored near the upper sides;
- the pitch remains toward the bottom of the visible viewport;
- subtle atmospheric particles may continue moving independently.

For production, consider collapsing the scene/header controls into a compact sticky header while scrolling so long lists receive more vertical space.

## Motion and feedback direction

- Appearance changes: smoothly cross-fade grades and lighting without changing background geometry.
- Scene changes: short opacity and scale transition.
- Loading: football-specific Lottie animation rather than a generic spinner.
- Winner declaration: celebratory result presentation with confetti and a gold accent.
- Background: very subtle drifting particles for atmosphere.
- Honour Reduce Motion by stopping ambient movement and simplifying celebratory effects.

Motion should reinforce state changes and important moments, not run continuously at a distracting intensity.

## POC controls and scenes

The segmented control switches between:

- Games — game overview and mode-specific cards.
- Matchday — prediction/action-focused state.
- Loading — themed loading treatment.
- Winner — celebration and confetti treatment.

The sun/moon button demonstrates the shared stadium composition in light and dark modes.

## Share cards

Share cards should be modernised while continuing to look like part of the V2 app. They must use the real `V2Theme` tokens rather than a separate or approximate mode palette.

### Agreed format

- A share card is one complete, vertically scrollable image.
- It includes every player rather than showing only a top-eight summary.
- The image has a fixed width and a consistent, readable row height; its height grows with the player count.
- Recipients open the image in WhatsApp and zoom or scroll vertically.
- Do not dynamically shrink text to force more rows into a fixed-height social card.
- Keep the export optimised so a 100-player image remains practical to share.

The approved scale prototype is approximately 1080 x 5650 pixels for 100 players. Actual height may vary slightly by card type, but row text must remain readable at the same scale.

### Player limits and entitlement

- Ad/free mode is capped at 100 players per game.
- The complete single-image share card supports all players up to that cap.
- Games with more than 100 players require a subscription.
- The player limit must be enforced when adding or importing players, not only during card generation.
- For subscribed games above 100 players, use a compact summary share image plus a public Cloudflare standings link.
- The public link is future subscribed-mode work; ad mode must not depend on PWA links or additional cloud infrastructure.

### Mode styling

All cards share the V2 dark neutrals and status colours:

- Background: `#0B1220`
- Card surface: `#111A2B`
- Secondary/pill surface: `#1E2A3A`
- Primary text: `#F5F7FA`
- Secondary text: `#8B9AAE`
- Positive/through/alive: `#3EB489`
- Eliminated/out: `#E63946`

Mode identity is then applied as follows:

- Last Man Standing: `#4C9AFF`, rounded headings, player/pick/result columns.
- Predictor: `#6366F1`, monospaced identity, ranking/week/total columns.
- Killer: `#F2542D`, serif headings, player/lives/accuracy/status columns.

The mode colour identifies the game type. Green and red remain reserved for player state so mode identity is never confused with through/alive/out status.

### Rendering and WhatsApp

- Continue using a plain render-data snapshot and `ImageRenderer` at 3x.
- Render the whole table outside a `ScrollView`; `ImageRenderer` must receive its full calculated height.
- The in-app preview may use a `ScrollView` around the completed image.
- Sharing as a normal image allows WhatsApp's image viewer to zoom and scroll.
- If WhatsApp photo compression reduces clarity, optionally offer "Share original quality" using the PNG as a document attachment. This is still one image, not a PDF.
- Test 0, 1, 99 and 100 players, long names, localisation, ties, multiple winners and anonymous mode.

## Production handoff notes

Do not wire `V2ExperienceThemePOC` directly into the shipping app. Use it as the design reference for extracting production components and tokens.

Suggested implementation order:

1. Create production background and lighting components with shared light/dark geometry.
2. Move approved colours, materials, spacing, and motion timings into the V2 design system.
3. Apply the treatment to one representative V2 Games screen and verify long-list scrolling, safe areas, Dynamic Type, contrast, and Reduce Motion.
4. Extend the approved system across Matchday, Loading, and Winner states.
5. Implement the agreed single-image share cards with the 100-player boundary.
6. Add the subscribed-mode public Cloudflare result link as separate future work.
7. Review the PWA last; it is a separate implementation and is already in a comparatively good state.

## Current status

- Isolated POC only.
- No production route or startup wiring.
- Light-first stadium composition agreed in principle.
- Dark mode derives from the same image.
- Fixed-background long-list behaviour established.
- Share-card scaling direction agreed: one complete tall image up to 100 players.
- Share-card colours and typography now mirror the real V2 mode tokens.
- More than 100 players is a subscription boundary with a future public Cloudflare link.
- The iOS project builds successfully with the POC present.
