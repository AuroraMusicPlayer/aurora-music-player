// Settings store — theme, accent, and behaviour preferences.
// Persisted to localStorage (small, synchronous, fine for SSR-guarded access).

import { create } from "zustand";
import { ACCENT_PRESETS, type ThemeMode } from "../lib/types";

interface SettingsState {
  theme: ThemeMode;
  accentName: string;
  animations: boolean;
  language: string;
  hydrated: boolean;
  setTheme: (t: ThemeMode) => void;
  setAccent: (name: string) => void;
  setAnimations: (v: boolean) => void;
  setLanguage: (l: string) => void;
  hydrate: () => void;
}

const STORAGE_KEY = "aurora-settings";

function persist(state: Partial<SettingsState>) {
  if (typeof localStorage === "undefined") return;
  try {
    const current = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...current, ...state }));
  } catch {
    /* ignore */
  }
}

function resolveTheme(theme: ThemeMode): "light" | "dark" | "amoled" {
  if (theme === "system") {
    if (typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches)
      return "dark";
    return "light";
  }
  return theme;
}

export function applyTheme(theme: ThemeMode, accentName: string, animations: boolean) {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  const resolved = resolveTheme(theme);
  root.classList.remove("light", "dark", "amoled");
  root.classList.add(resolved);
  const accent = ACCENT_PRESETS.find((a) => a.name === accentName) ?? ACCENT_PRESETS[0];
  root.style.setProperty("--accent", accent.value);
  root.style.setProperty("--accent-strong", accent.strong);
  root.classList.toggle("reduce-anim", !animations);
  // Theme-color meta for PWA / browser chrome.
  let meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) {
    meta = document.createElement("meta");
    meta.setAttribute("name", "theme-color");
    document.head.appendChild(meta);
  }
  meta.setAttribute("content", resolved === "light" ? "#ffffff" : resolved === "amoled" ? "#000000" : "#1a1a2e");
}

export const useSettings = create<SettingsState>((set, get) => ({
  theme: "dark",
  accentName: "Aurora",
  animations: true,
  language: "English",
  hydrated: false,

  setTheme: (theme) => {
    set({ theme });
    persist({ theme });
    const { accentName, animations } = get();
    applyTheme(theme, accentName, animations);
  },
  setAccent: (accentName) => {
    set({ accentName });
    persist({ accentName });
    const { theme, animations } = get();
    applyTheme(theme, accentName, animations);
  },
  setAnimations: (animations) => {
    set({ animations });
    persist({ animations });
    const { theme, accentName } = get();
    applyTheme(theme, accentName, animations);
  },
  setLanguage: (language) => {
    set({ language });
    persist({ language });
  },

  hydrate: () => {
    if (typeof localStorage === "undefined" || get().hydrated) return;
    try {
      const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
      const theme: ThemeMode = raw.theme ?? "dark";
      const accentName: string = raw.accentName ?? "Aurora";
      const animations: boolean = raw.animations ?? true;
      const language: string = raw.language ?? "English";
      set({ theme, accentName, animations, language, hydrated: true });
      applyTheme(theme, accentName, animations);
    } catch {
      set({ hydrated: true });
      applyTheme("dark", "Aurora", true);
    }
  },
}));
