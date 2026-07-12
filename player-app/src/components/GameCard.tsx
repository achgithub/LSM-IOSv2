import { useEffect, useState } from 'react';
import type { EligibleTeam, Fixture, Game, PredictorScore } from '../types';
import { submitLMS, submitPredictor, RoundMovedOnError } from '../api';
import { formatDate, kickoffParts } from '../format';
import { useT } from '../i18n';

function Kickoff({ value }: { value?: string | null }) {
  const parts = kickoffParts(value);
  if (!parts) return <span className="w-14 shrink-0" />;
  return (
    <span className="grid w-14 shrink-0 text-center text-[0.68rem] font-extrabold leading-none text-slate-400">
      <span>{parts[0]}</span>
      <span>{parts[1]}</span>
    </span>
  );
}

function StatusPill({ game }: { game: Game }) {
  const t = useT();
  const prior = game.priorSubmission;
  if (prior?.status === 'pending') {
    return (
      <span className="whitespace-nowrap rounded-full border border-warning/30 bg-warning/12 px-2.5 py-1 text-[0.68rem] font-bold text-amber-300">
        {t('status.submitted')}
      </span>
    );
  }
  if (prior?.status === 'approved') {
    return (
      <span className="whitespace-nowrap rounded-full border border-success/30 bg-success/12 px-2.5 py-1 text-[0.68rem] font-bold text-emerald-300">
        {t('status.approved')}
      </span>
    );
  }
  return (
    <span className="whitespace-nowrap rounded-full border border-danger/30 bg-danger/12 px-2.5 py-1 text-[0.68rem] font-bold text-red-300">
      {t('status.needsAttention')}
    </span>
  );
}

function ModeIcon({ isPredictor }: { isPredictor: boolean }) {
  return (
    <span
      className={`inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-xs font-black ${
        isPredictor ? 'bg-predictor-dim text-predictor' : 'bg-lms-dim text-lms'
      }`}
    >
      {isPredictor ? 'PRE' : 'LMS'}
    </span>
  );
}

// Slim, read-only recap of what was submitted — LMS already shows "Picked
// X", but Predictor previously just said "under review" with no scores.
// Players forget what they guessed and end up asking the manager, so this
// mirrors the score grid at a glance instead of making them ask.
function PredictorSummary({
  game,
  scores,
}: {
  game: Game;
  scores: { fixtureId: number; home: number; away: number; isJoker?: boolean }[] | null;
}) {
  const t = useT();
  if (!scores || scores.length === 0) {
    return <p className="m-0 p-3.5 text-slate-400">{t('game.pickReviewPending')}</p>;
  }
  const fixturesById = new Map((game.fixtures ?? []).map((f) => [f.fixtureId, f]));

  return (
    <div className="grid gap-1 p-3.5">
      {scores.map((score) => {
        const fixture = fixturesById.get(score.fixtureId);
        if (!fixture) return null;
        return (
          <div key={score.fixtureId} className="flex items-center justify-between gap-2 text-sm">
            <span className="min-w-0 flex-1 truncate text-right text-slate-300">{fixture.home}</span>
            <span className="shrink-0 font-bold text-slate-100">
              {score.home} - {score.away}
            </span>
            <span className="min-w-0 flex-1 truncate text-slate-300">{fixture.away}</span>
            {game.jokerEnabled && (
              <span className={`w-4 shrink-0 text-center text-xs font-black ${score.isJoker ? 'text-predictor' : 'text-transparent'}`}>J</span>
            )}
          </div>
        );
      })}
    </div>
  );
}

export function GameCard({
  game,
  token,
  onChanged,
  updateAvailable,
}: {
  game: Game;
  token: string;
  onChanged: () => void;
  updateAvailable: boolean;
}) {
  const t = useT();
  const isPredictor = game.mode === 'predictor';
  const roundLabel = isPredictor ? t('game.matchday', { n: game.roundNumber }) : t('game.round', { n: game.roundNumber });
  const title = game.gameName || roundLabel;
  const prior = game.priorSubmission;

  const [localSubmitted, setLocalSubmitted] = useState(false);
  const [pickedTeamName, setPickedTeamName] = useState<string | null>(null);
  const [submittedScores, setSubmittedScores] = useState<PredictorScore[] | null>(null);

  // GameCard instances persist across refreshes (keyed on gameToken), so a
  // stale `localSubmitted` from an earlier submit would otherwise survive a
  // manager's rejection and keep showing the "under review" summary forever
  // instead of the resubmission form. Resync to the server's word whenever
  // a fresh rejection comes in.
  useEffect(() => {
    if (prior?.status === 'rejected') {
      setLocalSubmitted(false);
      setPickedTeamName(null);
      setSubmittedScores(null);
    }
  }, [prior?.status]);

  const submitted = localSubmitted || prior?.status === 'pending' || prior?.status === 'approved';

  return (
    <article className="animate-card-in overflow-hidden rounded-2xl border border-white/10 bg-surface shadow-[0_16px_40px_rgba(0,0,0,0.35)]">
      <header className="flex items-center gap-3 border-b border-white/10 p-3.5">
        <ModeIcon isPredictor={isPredictor} />
        <div className="min-w-0 flex-1">
          <h2 className="m-0 truncate text-[clamp(0.98rem,4.2vw,1.2rem)] font-bold leading-tight">{title}</h2>
          {game.deadline && (
            <p className="m-0 mt-0.5 text-xs text-slate-400">{t('game.cutoff', { date: formatDate(game.deadline) ?? '' })}</p>
          )}
        </div>
        <StatusPill game={game} />
      </header>

      <div>
        {submitted ? (
          isPredictor ? (
            <PredictorSummary game={game} scores={submittedScores ?? prior?.payload?.scores ?? null} />
          ) : (
            <p className="m-0 p-3.5 text-slate-400">
              {pickedTeamName
                ? t('game.picked', { team: pickedTeamName })
                : prior?.payload?.teamName
                  ? t('game.picked', { team: prior.payload.teamName })
                  : t('game.pickReviewPending')}
            </p>
          )
        ) : (
          <>
            {prior?.status === 'rejected' && (
              <p className="m-0 p-3.5 pb-0 text-sm text-red-300">{t('game.rejected')}</p>
            )}
            {isPredictor ? (
              <PredictorSection
                game={game}
                token={token}
                updateAvailable={updateAvailable}
                onSubmitted={(scores) => {
                  setLocalSubmitted(true);
                  setSubmittedScores(scores);
                  onChanged();
                }}
              />
            ) : (
              <LMSSection
                game={game}
                token={token}
                updateAvailable={updateAvailable}
                onSubmitted={(teamName) => {
                  setLocalSubmitted(true);
                  setPickedTeamName(teamName);
                  onChanged();
                }}
              />
            )}
          </>
        )}
      </div>
    </article>
  );
}

function LMSSection({
  game,
  token,
  onSubmitted,
  updateAvailable,
}: {
  game: Game;
  token: string;
  onSubmitted: (teamName: string) => void;
  updateAvailable: boolean;
}) {
  const t = useT();
  const eligibleTeams = game.eligibleTeams ?? [];
  const fixtures = game.fixtures ?? [];
  // Keyed on (fixtureId, name) rather than name alone — a team can appear
  // twice in one round on rearranged fixtures, each occurrence eligible
  // independently (win one, lose the other), so a name-only key would let
  // the second occurrence silently overwrite the first.
  const eligibleIdByFixtureAndName = new Map(eligibleTeams.map((team) => [`${team.fixtureId ?? ''}:${team.name}`, team.id]));

  const [selection, setSelection] = useState<{ teamId: number; teamName: string; fixtureId: number | null; opponentName: string | null } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (eligibleTeams.length === 0) {
    return (
      <section className="grid gap-2 p-3.5">
        <p className="m-0 font-medium">{t('lms.noTeamsTitle')}</p>
        <p className="m-0 text-sm text-slate-400">{t('lms.noTeamsBody')}</p>
      </section>
    );
  }

  async function submit() {
    if (!selection || busy || updateAvailable) return;
    setBusy(true);
    setError(null);
    try {
      await submitLMS(token, game.gameToken, game.roundNumber, selection);
      onSubmitted(selection.teamName);
    } catch (e) {
      setError(e instanceof RoundMovedOnError ? t('error.roundMovedOn') : e instanceof Error ? e.message : 'Submit failed');
    } finally {
      setBusy(false);
    }
  }

  function TeamButton({ name, id, fixtureId = null, opponentName = null }: { name: string; id: number | undefined; fixtureId?: number | null; opponentName?: string | null }) {
    const eligible = id != null;
    const selected = eligible && selection?.teamId === id && selection?.fixtureId === fixtureId;
    return (
      <button
        type="button"
        disabled={!eligible}
        aria-pressed={selected}
        onClick={() => setSelection({ teamId: id!, teamName: name, fixtureId, opponentName })}
        className={`min-h-[2.7rem] overflow-hidden text-ellipsis whitespace-nowrap rounded-xl border px-2.5 py-1.5 text-sm font-bold transition-colors ${
          selected
            ? 'border-lms/60 bg-lms/18 text-orange-200'
            : 'border-white/10 bg-bg/50 text-slate-200 disabled:opacity-40'
        }`}
      >
        {name}
      </button>
    );
  }

  return (
    <section className="grid gap-3 p-3.5">
      <span className="text-[1.05rem] font-bold">{t('lms.pickTeam')}</span>
      <div className="grid gap-2">
        {fixtures.length > 0
          ? fixtures.map((fixture: Fixture) => (
              <div
                key={fixture.fixtureId}
                className="grid grid-cols-[3.45rem_minmax(0,1fr)] items-center gap-2 rounded-xl border border-white/10 bg-white/[0.04] p-2.5"
              >
                <Kickoff value={fixture.kickoff} />
                <div className="grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-2">
                  <TeamButton
                    name={fixture.home}
                    id={eligibleIdByFixtureAndName.get(`${fixture.fixtureId}:${fixture.home}`)}
                    fixtureId={fixture.fixtureId}
                    opponentName={fixture.away}
                  />
                  <span className="text-sm font-bold text-slate-500">{t('lms.vs')}</span>
                  <TeamButton
                    name={fixture.away}
                    id={eligibleIdByFixtureAndName.get(`${fixture.fixtureId}:${fixture.away}`)}
                    fixtureId={fixture.fixtureId}
                    opponentName={fixture.home}
                  />
                </div>
              </div>
            ))
          : eligibleTeams.map((team: EligibleTeam) => (
              <div key={`${team.fixtureId ?? ''}:${team.id}`} className="rounded-xl border border-white/10 bg-white/[0.04] p-2.5">
                <TeamButton name={team.name} id={team.id} fixtureId={team.fixtureId ?? null} opponentName={team.opponentName ?? null} />
              </div>
            ))}
      </div>
      {updateAvailable && <p className="m-0 text-sm text-red-300">{t('update.blocksSubmit')}</p>}
      {error && <p className="m-0 text-sm text-red-300">{error}</p>}
      <button
        type="button"
        disabled={!selection || busy || updateAvailable}
        onClick={submit}
        className="min-h-[2.9rem] rounded-xl bg-lms px-4 py-3 font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
      >
        {busy ? t('lms.submitting') : t('lms.submit')}
      </button>
    </section>
  );
}

function PredictorSection({
  game,
  token,
  onSubmitted,
  updateAvailable,
}: {
  game: Game;
  token: string;
  onSubmitted: (scores: PredictorScore[]) => void;
  updateAvailable: boolean;
}) {
  const t = useT();
  const fixtures = game.fixtures ?? [];
  const [scores, setScores] = useState<Record<number, { home: string; away: string }>>({});
  const [joker, setJoker] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function scoreFor(fixtureId: number) {
    return scores[fixtureId] ?? { home: '', away: '' };
  }

  function isFilled(value: string) {
    return value.trim() !== '' && !Number.isNaN(parseInt(value, 10));
  }

  const allFilled =
    fixtures.length > 0 &&
    fixtures.every((f) => {
      const value = scoreFor(f.fixtureId);
      return isFilled(value.home) && isFilled(value.away);
    });

  async function submit() {
    if (busy || !allFilled || updateAvailable) return;
    setBusy(true);
    setError(null);
    const payload: PredictorScore[] = fixtures.map((f) => ({
      fixtureId: f.fixtureId,
      home: parseInt(scoreFor(f.fixtureId).home, 10) || 0,
      away: parseInt(scoreFor(f.fixtureId).away, 10) || 0,
      isJoker: Boolean(game.jokerEnabled) && joker === f.fixtureId,
    }));
    try {
      await submitPredictor(token, game.gameToken, game.roundNumber, payload);
      onSubmitted(payload);
    } catch (e) {
      setError(e instanceof RoundMovedOnError ? t('error.roundMovedOn') : e instanceof Error ? e.message : 'Submit failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="grid gap-3 p-3.5">
      <div className="grid max-h-[min(31rem,58vh)] gap-2 overflow-y-auto pr-0.5 [overscroll-behavior:contain]">
        {fixtures.map((fixture) => {
          const value = scoreFor(fixture.fixtureId);
          const isJoker = game.jokerEnabled && joker === fixture.fixtureId;
          return (
            <div key={fixture.fixtureId} className="rounded-xl border border-white/10 bg-white/[0.04] px-2.5 py-2">
              {fixture.kickoff && (
                <p className="m-0 mb-1 text-[0.68rem] font-semibold text-slate-500">{formatDate(fixture.kickoff)}</p>
              )}
              <div
                className={
                  game.jokerEnabled
                    ? 'grid grid-cols-[minmax(0,1fr)_2.65rem_auto_2.65rem_minmax(0,1fr)_2rem] items-center gap-1 max-[480px]:grid-cols-[minmax(0,1fr)_2.25rem_2.25rem_minmax(0,1fr)_1.85rem] max-[480px]:gap-0.5'
                    : 'grid grid-cols-[minmax(0,1fr)_2.65rem_auto_2.65rem_minmax(0,1fr)] items-center gap-1 max-[480px]:grid-cols-[minmax(0,1fr)_2.25rem_2.25rem_minmax(0,1fr)] max-[480px]:gap-0.5'
                }
              >
                <span className="min-w-0 overflow-hidden text-ellipsis whitespace-nowrap text-right text-sm font-bold">{fixture.home}</span>
                <input
                  type="number"
                  inputMode="numeric"
                  min={0}
                  max={999}
                  placeholder="0"
                  aria-label={t('predictor.homeScoreLabel', { team: fixture.home })}
                  value={value.home}
                  onChange={(e) => setScores((s) => ({ ...s, [fixture.fixtureId]: { ...scoreFor(fixture.fixtureId), home: e.target.value } }))}
                  className="min-h-[2.3rem] w-full rounded-lg border border-white/10 bg-bg/60 text-center font-bold placeholder:font-normal placeholder:text-white/15"
                />
                <span className="text-center font-bold text-slate-500 max-[480px]:hidden">-</span>
                <input
                  type="number"
                  inputMode="numeric"
                  min={0}
                  max={999}
                  placeholder="0"
                  aria-label={t('predictor.homeScoreLabel', { team: fixture.away })}
                  value={value.away}
                  onChange={(e) => setScores((s) => ({ ...s, [fixture.fixtureId]: { ...scoreFor(fixture.fixtureId), away: e.target.value } }))}
                  className="min-h-[2.3rem] w-full rounded-lg border border-white/10 bg-bg/60 text-center font-bold placeholder:font-normal placeholder:text-white/15"
                />
                <span className="min-w-0 overflow-hidden text-ellipsis whitespace-nowrap text-sm font-bold">{fixture.away}</span>
                {game.jokerEnabled && (
                  <button
                    type="button"
                    title={t('predictor.joker')}
                    aria-label={t('predictor.jokerLabel', { home: fixture.home, away: fixture.away })}
                    aria-pressed={isJoker}
                    onClick={() => setJoker((j) => (j === fixture.fixtureId ? null : fixture.fixtureId))}
                    className={`min-h-[2rem] min-w-[2rem] rounded-lg border font-black transition-colors ${
                      isJoker ? 'border-predictor/60 bg-predictor/25 text-predictor' : 'border-predictor/25 bg-predictor/10 text-predictor/80'
                    }`}
                  >
                    J
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
      {updateAvailable && <p className="m-0 text-sm text-red-300">{t('update.blocksSubmit')}</p>}
      {error && <p className="m-0 text-sm text-red-300">{error}</p>}
      <button
        type="button"
        disabled={busy || !allFilled || updateAvailable}
        onClick={submit}
        className="min-h-[2.9rem] rounded-xl bg-predictor px-4 py-3 font-bold text-[#06121E] transition-transform active:scale-[0.98] disabled:opacity-40"
      >
        {busy ? t('predictor.submitting') : t('predictor.submit')}
      </button>
    </section>
  );
}
