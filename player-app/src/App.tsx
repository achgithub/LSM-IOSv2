import { useEffect, useMemo, useState } from 'react';
import type { Game, GameMode, PlayerState } from './types';
import { fetchPlayer, MaintenanceError } from './api';
import { useUpdateAvailable } from './hooks/useUpdateAvailable';
import { useDeadlineCountdown } from './hooks/useDeadlineCountdown';
import { GameCard } from './components/GameCard';
import { ClosesSoonest } from './components/ClosesSoonest';
import { useT } from './i18n';
import { needsPlayerAction } from './gameStatus';

const MODE_DOT: Record<GameMode, string> = { lms: 'bg-lms', predictor: 'bg-predictor', killer: 'bg-killer' };

const TOKEN_STORAGE_KEY = 'lsm.playerSubmissionToken';
const TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function getUrlToken(): string | null {
  const m = location.pathname.match(/\/s\/([0-9a-f-]{36})(?:\/|$)/i);
  const token = m?.[1] ?? new URLSearchParams(location.search).get('token');
  if (!token || !TOKEN_RE.test(token)) return null;
  return token.toLowerCase();
}

function getRememberedToken(): string | null {
  try {
    const token = localStorage.getItem(TOKEN_STORAGE_KEY);
    return token && TOKEN_RE.test(token) ? token.toLowerCase() : null;
  } catch {
    return null;
  }
}

function pendingCount(games: Game[], mode?: GameMode): number {
  return games.filter((g) => (!mode || g.mode === mode) && needsPlayerAction(g)).length;
}

export default function App() {
  const t = useT();

  const [token] = useState<string | null>(() => {
    const urlToken = getUrlToken() ?? getRememberedToken();
    if (urlToken) {
      try {
        localStorage.setItem(TOKEN_STORAGE_KEY, urlToken);
      } catch {
        // Private browsing: the URL token still works without remembering it.
      }
    }
    return urlToken;
  });

  const [state, setState] = useState<PlayerState>(token ? { loading: true } : { error: t('error.missingToken') });
  const [activeMode, setActiveMode] = useState<GameMode | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const { updateAvailable, applyUpdate, checkForUpdate } = useUpdateAvailable();

  async function load() {
    if (!token) return;
    try {
      const data = await fetchPlayer(token);
      setState(data);
    } catch (e) {
      if (e instanceof MaintenanceError) {
        setState({ maintenance: true, error: e.message });
      } else {
        setState({ error: e instanceof Error ? e.message : t('error.loadFailed') });
      }
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  async function refresh() {
    if (!token || refreshing) return;
    setRefreshing(true);
    checkForUpdate();
    await load();
    setRefreshing(false);
  }

  const games = state.games ?? [];
  const modesPresent = useMemo(() => new Set(games.map((g) => g.mode)), [games]);

  useEffect(() => {
    if (activeMode && modesPresent.has(activeMode)) return;
    const order: GameMode[] = ['lms', 'predictor', 'killer'];
    const next =
      order.find((m) => modesPresent.has(m) && pendingCount(games, m) > 0) ??
      order.find((m) => modesPresent.has(m)) ??
      null;
    setActiveMode(next);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [games]);

  const showFilter = !state.loading && !state.error && games.length > 0;
  const visibleGames = activeMode ? games.filter((g) => g.mode === activeMode) : games;
  const totalPending = pendingCount(games);
  const modeLabels: Record<GameMode, string> = { lms: t('mode.lms'), predictor: t('mode.predictor'), killer: t('mode.killer') };
  const deadline = useDeadlineCountdown(games);

  return (
    <>
      <div className="blob blob-chrome" aria-hidden="true" />
      <div className="blob blob-predictor" aria-hidden="true" />
      <div className="relative z-[1] mx-auto flex min-h-[100dvh] w-full max-w-app flex-col gap-4 px-[clamp(0.75rem,2.8vw,1.25rem)] pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-[max(0.85rem,env(safe-area-inset-top))]">
        <section className="animate-card-in grid gap-3 rounded-[20px] border border-white/10 bg-surface p-[clamp(0.9rem,3vw,1.25rem)] shadow-[0_16px_40px_rgba(0,0,0,0.35)] backdrop-blur">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-start gap-2.5">
              <img src="/shield.png" alt="" aria-hidden="true" className="mt-0.5 h-7 w-7 shrink-0 opacity-40" />
              <div>
                {state.playerName ? (
                  <>
                    <h1 className="m-0 font-display text-[clamp(1.3rem,5vw,1.8rem)] font-bold leading-tight tracking-tight">
                      {t('hero.greeting', { name: state.playerName })}
                    </h1>
                    {state.managerName && (
                      <p className="m-0 mt-1 text-sm text-slate-400">{t('hero.manager', { name: state.managerName })}</p>
                    )}
                  </>
                ) : (
                  <h1 className="m-0 font-display text-[clamp(1.3rem,5vw,1.8rem)] font-bold leading-tight tracking-tight">
                    {state.loading ? t('hero.loading') : t('hero.title')}
                  </h1>
                )}
              </div>
            </div>
            <div className="relative flex flex-wrap items-center justify-end gap-1.5">
              <button
                type="button"
                aria-label={updateAvailable ? t('update.applyNow') : t('hero.refresh')}
                onClick={updateAvailable ? applyUpdate : refresh}
                className={`inline-flex min-h-[2.5rem] min-w-[2.5rem] items-center justify-center rounded-full border transition-colors ${
                  updateAvailable
                    ? 'border-danger/50 bg-danger/15 text-red-300 hover:bg-danger/25'
                    : 'border-white/10 bg-surface text-slate-300 hover:bg-surface-hover'
                }`}
              >
                <svg viewBox="0 0 24 24" aria-hidden className={`h-[1.1rem] w-[1.1rem] ${refreshing ? 'animate-refresh-spin' : ''}`}>
                  <path
                    fill="currentColor"
                    d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"
                  />
                </svg>
              </button>
            </div>
          </div>

          {showFilter && (
            <div className="relative flex min-h-[2.75rem] items-center gap-2.5 rounded-2xl border border-white/10 bg-surface px-3.5 py-2.5">
              <span className={`h-2 w-2 shrink-0 rounded-full ${MODE_DOT[activeMode ?? 'lms']}`} aria-hidden="true" />
              <span className="whitespace-nowrap text-[13.5px] font-medium text-slate-400">
                {t('hero.games')} <span className="font-bold text-slate-100">{games.length}</span>
              </span>
              {totalPending > 0 && (
                <span className="whitespace-nowrap rounded-full bg-lms/20 px-2.5 py-1 text-[11px] font-bold text-orange-200">
                  {t('hero.needsYou', { count: totalPending })}
                </span>
              )}
              <span className="ml-auto shrink-0 text-slate-500" aria-hidden="true">
                ⌄
              </span>
              <select
                aria-label={t('hero.games')}
                value={activeMode ?? ''}
                onChange={(e) => setActiveMode((e.target.value || null) as GameMode | null)}
                className="absolute inset-0 h-full w-full cursor-pointer appearance-none opacity-0"
              >
                {(['lms', 'predictor', 'killer'] as GameMode[])
                  .filter((m) => modesPresent.has(m))
                  .map((m) => {
                    const pending = pendingCount(games, m);
                    return (
                      <option key={m} value={m}>
                        {pending > 0 ? `${modeLabels[m]} (${pending})` : modeLabels[m]}
                      </option>
                    );
                  })}
              </select>
            </div>
          )}
        </section>

        {deadline && <ClosesSoonest deadline={deadline} />}

        {updateAvailable && (
          <div className="animate-card-in flex items-center justify-between gap-3 rounded-xl border border-danger/40 bg-danger/15 px-4 py-2.5 text-sm text-red-200">
            <span className="font-semibold">{t('update.banner')}</span>
            <button
              type="button"
              onClick={applyUpdate}
              className="whitespace-nowrap rounded-full bg-danger px-3 py-1.5 text-xs font-bold text-white"
            >
              {t('update.applyNow')}
            </button>
          </div>
        )}

        <section aria-live="polite" className="grid gap-3">
          {state.loading ? (
            <Notice title={t('notice.loadingTitle')} message={t('notice.loadingBody')} />
          ) : state.maintenance ? (
            <Notice title={t('notice.maintenanceTitle')} message={state.error || t('notice.maintenanceBody')} />
          ) : state.error ? (
            <Notice title={t('notice.errorTitle')} message={state.error} error />
          ) : games.length === 0 ? (
            <Notice title={t('notice.noGamesTitle')} message={t('notice.noGamesBody')} />
          ) : (
            <div className="grid gap-3 md:grid-cols-[repeat(auto-fit,minmax(22rem,1fr))] md:items-start">
              {visibleGames.map((game) => (
                <GameCard key={game.gameToken} game={game} token={token!} onChanged={refresh} updateAvailable={updateAvailable} />
              ))}
            </div>
          )}
        </section>

        <footer className="mt-auto p-2 text-center text-sm text-slate-500">{t('footer.reviewed')}</footer>
      </div>
    </>
  );
}

function Notice({ title, message, error }: { title: string; message: string; error?: boolean }) {
  return (
    <section
      className={`animate-card-in grid gap-2 rounded-2xl border p-[clamp(0.9rem,3vw,1.25rem)] shadow-[0_16px_40px_rgba(0,0,0,0.35)] ${
        error ? 'border-danger/40 bg-surface' : 'border-white/10 bg-surface'
      }`}
    >
      <h2 className="m-0 text-lg font-bold">{title}</h2>
      <p className="m-0 text-slate-400">{message}</p>
    </section>
  );
}
