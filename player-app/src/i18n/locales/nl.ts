// TODO: translate — placeholder content is identical to en.ts.
// The explicit `Translations` annotation below enforces key parity with
// en.ts at compile time: adding/removing/renaming a key in en.ts without
// updating this file is a type error, not a silent runtime fallback.
import type { Translations } from './en';

const nl: Translations = {
  hero: {
    greeting: 'Hi {name}',
    manager: 'Manager: {name}',
    loading: 'Loading…',
    title: 'Last Stand Manager',
    refresh: 'Refresh',
    notifications: 'Notifications',
    games: 'Games',
  },
  mode: {
    lms: 'Last Man Standing',
    predictor: 'Predictor',
  },
  update: {
    banner: 'A new version is available',
    applyNow: 'Update now',
    blocksSubmit: 'Update the app before submitting to make sure your pick is sent correctly.',
  },
  notice: {
    loadingTitle: 'Loading your link',
    loadingBody: "Checking what your manager has opened for you.",
    errorTitle: "We couldn't open this link",
    noGamesTitle: 'No active rounds right now',
    noGamesBody: 'Check back when your manager opens the next round.',
    maintenanceTitle: 'Down for maintenance',
    maintenanceBody: "We're doing scheduled maintenance — back shortly.",
  },
  error: {
    missingToken: 'This link is missing its token. Check the URL and try again.',
    loadFailed: "Couldn't load your link. It may have expired or been revoked.",
    roundMovedOn: 'This round has moved on — refresh to see the latest.',
  },
  footer: {
    reviewed: "Submissions are reviewed by your game's manager before they go live.",
  },
  push: {
    enable: 'Enable',
    turnOff: 'Turn off',
    enabled: 'Notifications enabled',
    blocked: 'Blocked in browser settings.',
    unsupported: 'Install to home screen to enable push notifications.',
    installHint: 'Only available if saved to mobile home screen.',
  },
  status: {
    submitted: 'Submitted',
    approved: 'Approved',
    needsAttention: 'Needs attention',
  },
  game: {
    round: 'Round {n}',
    matchday: 'Matchday {n}',
    cutoff: 'Cutoff {date}',
    rejected: 'Rejected — pick again.',
    pickReviewPending: 'Your manager will review it before it goes live.',
    picked: 'Picked {team}.',
  },
  lms: {
    noTeamsTitle: 'No eligible teams found',
    noTeamsBody: 'Contact your manager.',
    pickTeam: 'Pick a team',
    submitting: 'Submitting…',
    submit: 'Submit pick',
    vs: 'v',
  },
  predictor: {
    submitting: 'Submitting…',
    submit: 'Submit predictions',
    joker: 'Joker',
    jokerLabel: 'Joker for {home} v {away}',
    homeScoreLabel: '{team} score',
  },
}

export default nl;
