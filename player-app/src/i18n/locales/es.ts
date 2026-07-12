// TODO: translate — placeholder content is identical to en.ts.
// The explicit `Translations` annotation below enforces key parity with
// en.ts at compile time: adding/removing/renaming a key in en.ts without
// updating this file is a type error, not a silent runtime fallback.
import type { Translations } from './en';

const es: Translations = {
  hero: {
    greeting: 'Hi {name}',
    manager: 'Manager: {name}',
    loading: 'Loading…',
    title: 'Last Stand Manager',
    refresh: 'Refresh',
    games: 'Games',
    needsYou: '{count} needs you',
  },
  mode: {
    lms: 'Last Man Standing',
    predictor: 'Predictor',
    killer: 'Killer',
  },
  deadline: {
    closesIn: '{game} closes in {time}',
    soonestLabel: 'Closes soonest',
    days: 'Days',
    hours: 'Hrs',
    minutes: 'Min',
    seconds: 'Sec',
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
    deadlinePassed: 'The deadline for this round has passed.',
  },
  footer: {
    reviewed: "Submissions are reviewed by your game's manager before they go live.",
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
    historyLms: 'Round {n}: picked {team}',
    historyPredictor: 'Round {n}: {count} predictions submitted',
    historyResultLmsSurvived: 'Round {n}: survived ({team})',
    historyResultLmsEliminated: 'Round {n}: eliminated ({team})',
    historyResultPredictor: 'Round {n}: {points} pts ({total} total, {position} place)',
    historyResultKillerAlive: 'Round {n}: {lives} lives remaining',
    historyResultKillerEliminated: 'Round {n}: eliminated',
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
  killer: {
    pickOutcome: 'Pick the outcome',
    submitting: 'Submitting…',
    submit: 'Submit picks',
    home: 'Home',
    draw: 'Draw',
    away: 'Away',
    submittedCount: '{count} picks submitted',
    pickTarget: 'Pick your target',
  },
}

export default es;
