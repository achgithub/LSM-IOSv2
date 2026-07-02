import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import en from './locales/en';
import de from './locales/de';
import es from './locales/es';
import fr from './locales/fr';
import it from './locales/it';
import nl from './locales/nl';
import type { Translations } from './locales/en';

export const SUPPORTED_LOCALES = ['en', 'de', 'es', 'fr', 'it', 'nl'] as const;
export type Locale = (typeof SUPPORTED_LOCALES)[number];

const DICTIONARIES: Record<Locale, Translations> = { en, de, es, fr, it, nl };
const STORAGE_KEY = 'lsm.locale';

function isLocale(value: string): value is Locale {
  return (SUPPORTED_LOCALES as readonly string[]).includes(value);
}

function detectLocale(): Locale {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored && isLocale(stored)) return stored;
  } catch {
    // Private browsing: fall through to browser language detection.
  }
  for (const tag of navigator.languages ?? [navigator.language]) {
    const base = tag.split('-')[0].toLowerCase();
    if (isLocale(base)) return base;
  }
  return 'en';
}

// Leaf lookup by dot path, e.g. get(dict, 'hero.greeting'). Typed loosely —
// the call sites (useT's `t`) constrain valid keys via TranslationKey below.
function get(dict: Translations, path: string): string {
  return path.split('.').reduce<unknown>((node, part) => (node as Record<string, unknown>)?.[part], dict) as string;
}

function interpolate(template: string, vars?: Record<string, string | number>): string {
  if (!vars) return template;
  return template.replace(/\{(\w+)\}/g, (match, key) => (key in vars ? String(vars[key]) : match));
}

type Join<K extends string, V> = V extends string
  ? K
  : { [P in Extract<keyof V, string>]: Join<`${K}.${P}`, V[P]> }[Extract<keyof V, string>];
export type TranslationKey = { [K in Extract<keyof Translations, string>]: Join<K, Translations[K]> }[Extract<
  keyof Translations,
  string
>];

interface I18nContextValue {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

const I18nContext = createContext<I18nContextValue | null>(null);

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(detectLocale);

  const value = useMemo<I18nContextValue>(() => {
    const dict = DICTIONARIES[locale];
    return {
      locale,
      setLocale: (next: Locale) => {
        setLocaleState(next);
        try {
          localStorage.setItem(STORAGE_KEY, next);
        } catch {
          // Visual preference still applies for this page view.
        }
      },
      t: (key, vars) => interpolate(get(dict, key), vars),
    };
  }, [locale]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nContextValue {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error('useI18n must be used within I18nProvider');
  return ctx;
}

export function useT() {
  return useI18n().t;
}
