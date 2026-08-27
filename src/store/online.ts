import { create } from "zustand";
import type { OnlinePlaylist, OnlineTrack, PlayStat } from "../lib/types";

const STORAGE_KEY = "aurora-online-library-v1";
const MAX_HISTORY = 200;

interface PersistedOnlineLibrary {
  saved: OnlineTrack[];
  history: OnlineTrack[];
  playlists: OnlinePlaylist[];
  stats: Record<string, PlayStat>;
}

interface OnlineState extends PersistedOnlineLibrary {
  hydrated: boolean;
  current: OnlineTrack | null;
  hydrate: () => void;
  play: (track: OnlineTrack) => void;
  stop: () => void;
  saveTrack: (track: OnlineTrack) => void;
  removeSaved: (videoId: string) => void;
  importPlaylist: (name: string, tracks: OnlineTrack[]) => string;
  clearHistory: () => void;
}

function emptyLibrary(): PersistedOnlineLibrary {
  return { saved: [], history: [], playlists: [], stats: {} };
}

function load(): PersistedOnlineLibrary {
  if (typeof localStorage === "undefined") return emptyLibrary();
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    return {
      saved: Array.isArray(parsed.saved) ? parsed.saved : [],
      history: Array.isArray(parsed.history) ? parsed.history : [],
      playlists: Array.isArray(parsed.playlists) ? parsed.playlists : [],
      stats: parsed.stats && typeof parsed.stats === "object" ? parsed.stats : {},
    };
  } catch {
    return emptyLibrary();
  }
}

function persist(state: PersistedOnlineLibrary) {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function uid(prefix: string) {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;
}

export const useOnline = create<OnlineState>((set, get) => {
  const save = (partial: Partial<PersistedOnlineLibrary>) => {
    const current = get();
    const next = {
      saved: partial.saved ?? current.saved,
      history: partial.history ?? current.history,
      playlists: partial.playlists ?? current.playlists,
      stats: partial.stats ?? current.stats,
    };
    set(next);
    persist(next);
  };

  return {
    ...emptyLibrary(),
    hydrated: false,
    current: null,

    hydrate: () => {
      if (get().hydrated) return;
      set({ ...load(), hydrated: true });
    },

    play: (track) => {
      const state = get();
      const history = [
        { ...track, addedAt: Date.now() },
        ...state.history.filter((item) => item.videoId !== track.videoId),
      ].slice(0, MAX_HISTORY);
      const stats = { ...state.stats };
      const previous = stats[track.videoId] ?? { count: 0, lastPlayed: 0 };
      stats[track.videoId] = {
        count: previous.count + 1,
        lastPlayed: Date.now(),
      };
      set({ current: track });
      save({ history, stats });
    },

    stop: () => set({ current: null }),

    saveTrack: (track) => {
      const saved = [
        { ...track, addedAt: Date.now() },
        ...get().saved.filter((item) => item.videoId !== track.videoId),
      ];
      save({ saved });
    },

    removeSaved: (videoId) => {
      save({ saved: get().saved.filter((item) => item.videoId !== videoId) });
    },

    importPlaylist: (name, tracks) => {
      const state = get();
      const id = uid("online_playlist");
      const playlist: OnlinePlaylist = {
        id,
        name,
        videoIds: tracks.map((track) => track.videoId),
        createdAt: Date.now(),
      };
      const savedById = new Map(state.saved.map((track) => [track.videoId, track]));
      for (const track of tracks) savedById.set(track.videoId, track);
      save({
        saved: [...savedById.values()],
        playlists: [...state.playlists, playlist],
      });
      return id;
    },

    clearHistory: () => save({ history: [] }),
  };
});
