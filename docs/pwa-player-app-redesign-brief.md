# Sports Manager PWA Redesign Brief

Date: 28 June 2026
Status: planning / design handover. Current code and preview are draft, not signed off.

## Goal

Create a compact, mobile-first player PWA for non-technical users. The app must make the next action obvious, work well for users with poor eyesight, and avoid wasting screen space.

The PWA must handle:

- LMS submissions.
- Predictor submissions.
- Future game modes.
- Players who are in games run by more than one manager.

There is also a related non-PWA Predictor published league / recent matchday page that should eventually share the same compact branding.

## Locked Branding

- Brand: Sports Manager / Last Stand Manager.
- Visual tone: professional, dark navy, sports utility app, not a marketing landing page.
- Background: existing floodlight/stadium background image.
- Logo: existing shield asset.
- Saved PWA icon: shield logo.
- No licensed club crests, badges, kit graphics, or team logos.
- Team display: plain team names only.
- Main colours:
  - Base navy: `#0B1220`
  - Panel: `#121C2E`
  - Chrome blue: `#3DA8FF`
  - LMS orange: `#F97316`
  - Predictor blue: `#38BDF8`
  - Text: `#F8FAFC`
  - Muted text: `#94A3B8`
  - Success: `#22C55E`
  - Error / needs action: `#EF4444`
  - Submitted / pending: amber `#FBBF24`

## Accessibility Rules

- Body text should remain readable by default.
- Keep important tap targets practical on mobile.
- Add visible `Text +` / larger text toggle using `localStorage` key `lsm.largeText`.
- Never rely on colour only:
  - Red = `Needs action`
  - Amber = `Submitted`
  - Green = `Approved`
- Avoid tiny tables on mobile.
- Avoid long explanatory text in the main UI.

## Agreed PWA Layout

Top area should be very compact:

- `Hi Andy`
- `Manager: XYZ`
- Small `Save link`
- Small `Text +`
- Two mode buttons:
  - `LMS 1`
  - `PRED 1`

Avoid:

- Large brand header taking half the screen.
- Repeating game names.
- Big save-link cards.
- Big instructional text.

## Manager Identity Requirement

This is now on the to-do list and should be treated as required.

Reason: players may be in games run by multiple managers. The PWA and saved home-screen icon need to make it clear which manager the link belongs to.

Desired display:

- PWA page: `Hi Andy · Manager: XYZ`
- Saved app name: `LSM XYZ` or similar short label.

Suggested saved app name format:

- Prefer: `LSM Andy`
- Avoid: `LSM: Andy`, because punctuation and longer names truncate badly under phone icons.

Technical note:

- Dynamic PWA naming is possible because the app already uses token-specific manifests at `/s/<token>/manifest.webmanifest`.
- The Worker does not currently store a human manager name. It stores `managerSuffix`.
- Add manager display name to Worker storage and return it from `/s/:token`.
- Phones usually lock the PWA name at install time. If a manager later changes name, users may need to remove and re-add the PWA.

## LMS Behaviour

Use a dropdown, not 20 large buttons.

LMS card:

- Header row 1: `LMS` and status pill.
- Header row 2: `Round 4 · Sat 3 Aug 14:00`.
- Body:
  - Label: `Team`
  - Dropdown with all teams.
  - Previously used teams should be greyed out / disabled where this data is available.
  - Submit button below.

Important:

- If the backend already filters unavailable teams, the dropdown can show only eligible teams.
- If the product wants to show all 20 with previous picks greyed out, the payload must include both available and used teams, not only eligible teams.

## Predictor Behaviour

Do not use a dropdown. Use a compact scrollable fixture section.

Predictor card:

- Header row 1: `PRED` and status pill.
- Header row 2: `Matchday 5 · Fri 9 Aug 19:45`.
- Body:
  - Scrollable list of 10 fixtures.
  - Each fixture has its own date/time.
  - Team names appear once.
  - Score inputs are compact and support up to 3 digits.
  - Joker button is `J`, with tooltip / accessible label `Joker`.
  - Submit button below the scroll area.

On narrow screens:

- Fixture kickoff should split over two lines, for example:
  - `10 Aug`
  - `15:00`
- Hide the visual dash if needed to save width.
- Keep rows compact enough that the user can see several fixtures at once.

## PWA Save Link Behaviour

Keep an unobtrusive `Save link` action next to `Text +`.

Behaviour:

- Show it only when the page has a token and is not already installed / standalone.
- Chrome / Android: use `beforeinstallprompt` where available.
- Safari / iOS: remind the user to use the browser menu / Add to Home Screen.
- Do not copy/share the link automatically. These links are personal.

## Saved PWA Icon

Use the existing shield:

```json
"icons": [
  { "src": "/logo.png", "sizes": "192x192", "type": "image/png" },
  { "src": "/logo.png", "sizes": "512x512", "type": "image/png" },
  { "src": "/logo.png", "sizes": "1024x1024", "type": "image/png", "purpose": "any maskable" }
]
```

Also include:

```html
<link rel="apple-touch-icon" href="/logo.png">
<link rel="icon" type="image/png" href="/logo.png">
```

## Example HTML

This is a simplified target shape for the compact PWA. It is not meant to be a full app by itself.

```html
<main id="app">
  <section class="hero-panel compact-hero">
    <div class="top-line">
      <div>
        <h1>Hi Andy</h1>
        <p class="manager-line">Manager: XYZ</p>
      </div>
      <div class="header-actions">
        <button class="save-link-action" type="button">Save link</button>
        <button class="text-toggle" type="button" aria-pressed="false">Text +</button>
      </div>
    </div>

    <div class="mode-count-row" role="group" aria-label="Pending games">
      <button class="mode-count-pill lms" type="button" aria-pressed="true">
        <span>LMS</span>
        <strong>1</strong>
      </button>
      <button class="mode-count-pill predictor" type="button" aria-pressed="false">
        <span>PRED</span>
        <strong>1</strong>
      </button>
    </div>
  </section>

  <article class="game-card mode-lms">
    <header class="game-head">
      <div class="card-topline">
        <p class="eyebrow">LMS</p>
        <span class="card-status status-action">Needs action</span>
      </div>
      <h2>Round 4 · Sat 3 Aug 14:00</h2>
    </header>

    <section class="submission-section">
      <label class="team-picker">
        <span class="section-title">Team</span>
        <select class="team-select">
          <option value="">Choose team</option>
          <option value="1">Arsenal</option>
          <option value="2" disabled>Chelsea - used</option>
          <option value="3">Newcastle</option>
        </select>
      </label>
      <button class="btn btn-primary" type="button">Submit pick</button>
    </section>
  </article>

  <article class="game-card mode-predictor">
    <header class="game-head">
      <div class="card-topline">
        <p class="eyebrow">PRED</p>
        <span class="card-status status-action">Needs action</span>
      </div>
      <h2>Matchday 5 · Fri 9 Aug 19:45</h2>
    </header>

    <section class="submission-section">
      <div class="fixture-list predictor-scroll">
        <div class="fixture-row">
          <div class="compact-score-row">
            <span class="fixture-kickoff">
              <span>9 Aug</span>
              <span>19:45</span>
            </span>
            <span class="fixture-team home">Arsenal</span>
            <input class="score-input" type="number" inputmode="numeric" min="0" max="999" aria-label="Arsenal score">
            <span class="score-separator">-</span>
            <input class="score-input" type="number" inputmode="numeric" min="0" max="999" aria-label="Chelsea score">
            <span class="fixture-team away">Chelsea</span>
            <button class="joker-btn" type="button" title="Joker" aria-label="Joker for Arsenal v Chelsea">J</button>
          </div>
        </div>
      </div>
      <button class="btn btn-primary predictor-submit" type="button">Submit predictions</button>
    </section>
  </article>
</main>
```

## CSS Direction

Use plain CSS. No Tailwind/build step required.

Use:

- CSS variables.
- `rem`.
- `clamp()`.
- flex/grid.
- media queries.
- `:focus-visible`.
- `prefers-reduced-motion`.

Avoid:

- Decorative blobs/orbs.
- Big landing-page hero sections.
- Nested cards.
- Huge repeating headings.
- Team crests/logos.

## Implementation To-Do

1. Finalise the compact PWA UI with the approved layout.
2. Add manager display name to the Worker data model.
3. Add migration for manager display name.
4. Send manager name from iOS when minting links and pushing rounds.
5. Return manager name from `/s/:token`.
6. Show `Manager: XYZ` after `Hi Andy`.
7. Use manager name in `/s/:token/manifest.webmanifest`.
8. Keep shield as saved PWA icon.
9. Keep token-specific `start_url` as `/s/<token>`.
10. Keep `Save link` small next to `Text +`.
11. LMS: use dropdown; decide whether backend sends all teams plus used flags or only eligible teams.
12. Predictor: use compact scrollable rows with fixture-specific kickoff.
13. Apply the same compact brand system to the Predictor published league / recent matchday page.
14. Test on iOS Safari, Android Chrome, desktop Chrome, and desktop Safari.

## Test Checklist

- Missing token shows a clear error.
- Token in `/s/<uuid>` survives PWA install/open.
- Saved PWA icon is the shield.
- Saved PWA name uses manager identity where available.
- `Save link` appears only when useful.
- `Text +` persists with `localStorage`.
- LMS dropdown works with 20 teams.
- Previously used LMS teams are greyed/disabled if data is available.
- Predictor shows 10 fixtures in a compact scrollable area.
- Predictor rows fit on narrow screens without unusable truncation.
- Joker `J` is accessible and toggles correctly.
- Status is clear: red needs action, amber submitted, green approved.
- No team crests/badges/logos appear.
- Published Predictor page still respects CSP and PIN unlock flow.

