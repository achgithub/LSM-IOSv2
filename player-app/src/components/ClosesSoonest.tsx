import type { DeadlineCountdown } from '../hooks/useDeadlineCountdown';
import { countdownParts, formatDeadlineShort } from '../format';
import { useT } from '../i18n';

function ClockUnit({ value, label }: { value: number; label: string }) {
  return (
    <div className="flex-1 rounded-xl bg-black/35 px-1 py-2 pb-1.5 text-center">
      <div className="font-display text-[22px] font-bold leading-none tabular-nums text-white">
        {String(value).padStart(2, '0')}
      </div>
      <div className="mt-1 text-[10px] uppercase tracking-[0.05em] text-slate-500">{label}</div>
    </div>
  );
}

export function ClosesSoonest({ deadline }: { deadline: DeadlineCountdown }) {
  const t = useT();
  const { days, hours, minutes, seconds } = countdownParts(deadline.remainingMs);
  const name = deadline.game.gameName || t(`mode.${deadline.game.mode}`);
  const when = formatDeadlineShort(deadline.game.deadline);

  return (
    <div className="animate-card-in relative overflow-hidden rounded-[20px] border border-lms/50 bg-[linear-gradient(155deg,#3a2313,#2c1c10_60%,theme(colors.panel))] p-4 pb-[18px]">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-[30px] -top-[60px] h-[200px] w-[200px] rounded-full bg-[radial-gradient(circle,rgba(249,115,22,0.2),transparent_70%)]"
      />
      <div className="relative flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[0.06em] text-orange-300">
        <span className="h-1.5 w-1.5 rounded-full bg-lms shadow-[0_0_0_3px_rgba(249,115,22,0.3)]" />
        {t('deadline.soonestLabel')}
      </div>
      <div className="relative mb-3 mt-0.5 font-display text-base font-bold text-white">
        {name}
        {when && <span className="ml-1.5 font-sans text-[13px] font-medium text-slate-500">· {when}</span>}
      </div>
      <div className="relative flex gap-2">
        <ClockUnit value={days} label={t('deadline.days')} />
        <ClockUnit value={hours} label={t('deadline.hours')} />
        <ClockUnit value={minutes} label={t('deadline.minutes')} />
        <ClockUnit value={seconds} label={t('deadline.seconds')} />
      </div>
    </div>
  );
}
