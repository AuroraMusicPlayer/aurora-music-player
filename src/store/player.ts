// Aurora Music — main store. Owns the library (tracks, playlists, favorites,
// stats) and live playback state, and drives the audio engine.

import { create } from "zustand";
import {
  engine,
  setMediaSessionHandlers,
  setMediaSessionMeta,
  setMediaSessionPlaybackState,
} from "../lib/audio/engine";
import {
  loadLibrary,
  saveLibrary,
  getBlob,
  deleteBlob,
  isBrowser,
  type PersistedLibrary,
} from "../lib/db";
import {
  EQ_FREQUENCIES,
  EQ_PRESETS,
  type EqualizerState,
  type PlayStat,
  type Playlist,
  type RepeatMode,
  type Track,
} from "../lib/types";

const EQ_KEY = "aurora-eq";

function loadEq(): EqualizerState {
  const fallback: EqualizerState = {
    enabled: false,
    bands: new Array(EQ_FREQUENCIES.length).fill(0),
    preset: "Flat",
  };
  if (typeof localStorage === "undefined") return fallback;
  try {
    const raw = JSON.parse(localStorage.getItem(EQ_KEY) || "null");
    return raw ?? fallback;
  } catch {
    return fallback;
  }
}

function saveEq(eq: EqualizerState) {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(EQ_KEY, JSON.stringify(eq));
}

function uid(prefix: string) {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;
}

interface PlayerState {
  tracks: Track[];
  playlists: Playlist[];
  favorites: string[];
  stats: Record<string, PlayStat>;

  queue: string[];
  queueIndex: number;
  history: number[];

  currentId: string | null;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  rate: number;
  shuffle: boolean;
  repeat: RepeatMode;

  eq: EqualizerState;
  sleepTimerEnd: number | null;

  hydrated: boolean;
  scanning: boolean;
  playerOpen: boolean;

  hydrate: () => Promise<void>;
  addTracks: (tracks: Track[]) => void;
  removeTrack: (id: string) => Promise<void>;

  playTrack: (id: string, context?: string[]) => Promise<void>;
  playContext: (ids: string[], startIndex?: number) => Promise<void>;
  togglePlay: () => void;
  next: (auto?: boolean) => Promise<void>;
  prev: () => Promise<void>;
  seek: (t: number) => void;
  setVolume: (v: number) => void;
  setRate: (r: number) => void;
  toggleShuffle: () => void;
  cycleRepeat: () => void;

  toggleFavorite: (id: string) => void;

  addToQueue: (ids: string[]) => void;
  playNextInQueue: (id: string) => void;
  removeFromQueue: (index: number) => void;
  reorderQueue: (from: number, to: number) => void;
  clearQueue: () => void;

  createPlaylist: (name: string, ids?: string[]) => string;
  renamePlaylist: (id: string, name: string) => void;
  deletePlaylist: (id: string) => void;
  addToPlaylist: (playlistId: string, ids: string[]) => void;
  removeFromPlaylist: (playlistId: string, trackId: string) => void;

  setEqEnabled: (v: boolean) => void;
  setEqBand: (index: number, gain: number) => void;
  setEqPreset: (preset: string) => void;

  setSleepTimer: (minutes: number | null) => void;
  setPlayerOpen: (v: boolean) => void;
  dismiss: () => void;
}

let saveTimer: ReturnType<typeof setTimeout> | null = null;
let currentObjectUrl: string | null = null;
let sleepTimeout: ReturnType<typeof setTimeout> | null = null;

export const usePlayer = create<PlayerState>((set, get) => {
  function snapshot(): PersistedLibrary {
    const s = get();
    return {
      tracks: s.tracks,
      playlists: s.playlists,
      favorites: s.favorites,
      stats: s.stats,
      queue: s.queue,
      queueIndex: s.queueIndex,
    };
  }

  function saveSoon() {
    if (!isBrowser()) return;
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => void saveLibrary(snapshot()), 400);
  }

  function trackById(id: string | null): Track | undefined {
    if (!id) return undefined;
    return get().tracks.find((t) => t.id === id);
  }

  async function resolveSrc(track: Track): Promise<string | null> {
    if (track.source === "url") return track.url;
    const blob = await getBlob(track.id);
    if (!blob) return null;
    if (currentObjectUrl) URL.revokeObjectURL(currentObjectUrl);
    currentObjectUrl = URL.createObjectURL(blob);
    return currentObjectUrl;
  }

  async function loadAndPlay(id: string) {
    const track = trackById(id);
    if (!track) return;
    const src = await resolveSrc(track);
    if (!src) return;
    set({ currentId: id, currentTime: 0 });
    await engine.load(src, true);
    engine.setRate(get().rate);
    const eq = get().eq;
    engine.setEqEnabled(eq.enabled, eq.bands);
    setMediaSessionMeta({
      title: track.title,
      artist: track.artist,
      album: track.album,
      artwork: track.artwork,
    });
    // count play
    const stats = { ...get().stats };
    const prev = stats[id] ?? { count: 0, lastPlayed: 0 };
    stats[id] = { count: prev.count + 1, lastPlayed: Date.now() };
    set({ stats });
    saveSoon();
  }

  return {
    tracks: [],
    playlists: [],
    favorites: [],
    stats: {},
    queue: [],
    queueIndex: -1,
    history: [],
    currentId: null,
    isPlaying: false,
    currentTime: 0,
    duration: 0,
    volume: 1,
    rate: 1,
    shuffle: false,
    repeat: "off",
    eq: loadEq(),
    sleepTimerEnd: null,
    hydrated: false,
    scanning: false,
    playerOpen: false,

    hydrate: async () => {
      if (get().hydrated || !isBrowser()) return;
      engine.init();
      engine.setCallbacks({
        onTime: (t) => set({ currentTime: t }),
        onDuration: (d) => set({ duration: d }),
        onPlay: () => {
          set({ isPlaying: true });
          setMediaSessionPlaybackState("playing");
        },
        onPause: () => {
          set({ isPlaying: false });
          setMediaSessionPlaybackState("paused");
        },
        onEnded: () => void get().next(true),
        onError: () => set({ isPlaying: false }),
      });
      setMediaSessionHandlers({
        play: () => get().togglePlay(),
        pause: () => get().togglePlay(),
        next: () => void get().next(),
        prev: () => void get().prev(),
        seek: (t) => get().seek(t),
      });

      const lib = await loadLibrary();
      if (lib) {
        // Restore artwork object URLs from stored blobs.
        const tracks = await Promise.all(
          lib.tracks.map(async (t) => {
            if (t.source === "local") {
              const art = await getBlob(`art_${t.id}`);
              if (art) return { ...t, artwork: URL.createObjectURL(art) };
            }
            return { ...t, artwork: t.artwork };
          }),
        );
        set({
          tracks,
          playlists: lib.playlists ?? [],
          favorites: lib.favorites ?? [],
          stats: lib.stats ?? {},
          queue: lib.queue ?? [],
          queueIndex: lib.queueIndex ?? -1,
        });
      }
      set({ hydrated: true });
    },

    addTracks: (incoming) => {
      const existing = get().tracks;
      const merged = [...existing, ...incoming];
      set({ tracks: merged });
      saveSoon();
    },

    removeTrack: async (id) => {
      const s = get();
      set({
        tracks: s.tracks.filter((t) => t.id !== id),
        favorites: s.favorites.filter((f) => f !== id),
        playlists: s.playlists.map((p) => ({
          ...p,
          trackIds: p.trackIds.filter((tid) => tid !== id),
        })),
        queue: s.queue.filter((q) => q !== id),
      });
      await deleteBlob(id);
      await deleteBlob(`art_${id}`);
      saveSoon();
    },

    playContext: async (ids, startIndex = 0) => {
      if (ids.length === 0) return;
      set({ queue: ids, queueIndex: startIndex, history: [] });
      await loadAndPlay(ids[startIndex]);
      saveSoon();
    },

    playTrack: async (id, context) => {
      const ctx = context && context.length ? context : [id];
      const idx = ctx.indexOf(id);
      await get().playContext(ctx, idx >= 0 ? idx : 0);
    },

    togglePlay: () => {
      const { isPlaying, currentId, queue } = get();
      if (!currentId && queue.length > 0) {
        void get().playContext(queue, Math.max(0, get().queueIndex));
        return;
      }
      if (isPlaying) engine.pause();
      else void engine.play();
    },

    next: async (auto = false) => {
      const s = get();
      if (s.queue.length === 0) return;
      if (auto && s.repeat === "one") {
        engine.seek(0);
        await engine.play();
        return;
      }
      let nextIndex: number;
      if (s.shuffle && s.queue.length > 1) {
        do {
          nextIndex = Math.floor(Math.random() * s.queue.length);
        } while (nextIndex === s.queueIndex);
      } else {
        nextIndex = s.queueIndex + 1;
        if (nextIndex >= s.queue.length) {
          if (s.repeat === "all") nextIndex = 0;
          else {
            engine.pause();
            engine.seek(0);
            return;
          }
        }
      }
      set({ history: [...s.history, s.queueIndex], queueIndex: nextIndex });
      await loadAndPlay(s.queue[nextIndex]);
      saveSoon();
    },

    prev: async () => {
      const s = get();
      if (engine.currentTime > 3) {
        engine.seek(0);
        return;
      }
      let prevIndex: number;
      if (s.history.length > 0) {
        const h = [...s.history];
        prevIndex = h.pop()!;
        set({ history: h });
      } else {
        prevIndex = s.queueIndex - 1;
        if (prevIndex < 0) prevIndex = s.repeat === "all" ? s.queue.length - 1 : 0;
      }
      set({ queueIndex: prevIndex });
      await loadAndPlay(s.queue[prevIndex]);
      saveSoon();
    },

    seek: (t) => {
      engine.seek(t);
      set({ currentTime: t });
    },

    setVolume: (v) => {
      engine.setVolume(v);
      set({ volume: v });
    },

    setRate: (r) => {
      engine.setRate(r);
      set({ rate: r });
    },

    toggleShuffle: () => set((s) => ({ shuffle: !s.shuffle })),

    cycleRepeat: () =>
      set((s) => ({
        repeat: s.repeat === "off" ? "all" : s.repeat === "all" ? "one" : "off",
      })),

    toggleFavorite: (id) => {
      const fav = get().favorites;
      set({ favorites: fav.includes(id) ? fav.filter((f) => f !== id) : [...fav, id] });
      saveSoon();
    },

    addToQueue: (ids) => {
      set((s) => ({ queue: [...s.queue, ...ids] }));
      saveSoon();
    },

    playNextInQueue: (id) => {
      set((s) => {
        const q = [...s.queue];
        q.splice(s.queueIndex + 1, 0, id);
        return { queue: q };
      });
      saveSoon();
    },

    removeFromQueue: (index) => {
      set((s) => {
        const q = [...s.queue];
        q.splice(index, 1);
        let qi = s.queueIndex;
        if (index < qi) qi -= 1;
        return { queue: q, queueIndex: qi };
      });
      saveSoon();
    },

    reorderQueue: (from, to) => {
      set((s) => {
        const q = [...s.queue];
        const [moved] = q.splice(from, 1);
        q.splice(to, 0, moved);
        let qi = s.queueIndex;
        if (from === qi) qi = to;
        else if (from < qi && to >= qi) qi -= 1;
        else if (from > qi && to <= qi) qi += 1;
        return { queue: q, queueIndex: qi };
      });
      saveSoon();
    },

    clearQueue: () => {
      set({ queue: [], queueIndex: -1, history: [] });
      saveSoon();
    },

    createPlaylist: (name, ids = []) => {
      const pl: Playlist = {
        id: uid("pl"),
        name,
        trackIds: ids,
        createdAt: Date.now(),
      };
      set((s) => ({ playlists: [...s.playlists, pl] }));
      saveSoon();
      return pl.id;
    },

    renamePlaylist: (id, name) => {
      set((s) => ({
        playlists: s.playlists.map((p) => (p.id === id ? { ...p, name } : p)),
      }));
      saveSoon();
    },

    deletePlaylist: (id) => {
      set((s) => ({ playlists: s.playlists.filter((p) => p.id !== id) }));
      saveSoon();
    },

    addToPlaylist: (playlistId, ids) => {
      set((s) => ({
        playlists: s.playlists.map((p) =>
          p.id === playlistId
            ? { ...p, trackIds: [...new Set([...p.trackIds, ...ids])] }
            : p,
        ),
      }));
      saveSoon();
    },

    removeFromPlaylist: (playlistId, trackId) => {
      set((s) => ({
        playlists: s.playlists.map((p) =>
          p.id === playlistId
            ? { ...p, trackIds: p.trackIds.filter((t) => t !== trackId) }
            : p,
        ),
      }));
      saveSoon();
    },

    setEqEnabled: (v) => {
      const eq = { ...get().eq, enabled: v };
      engine.setEqEnabled(v, eq.bands);
      set({ eq });
      saveEq(eq);
    },

    setEqBand: (index, gain) => {
      const bands = [...get().eq.bands];
      bands[index] = gain;
      const eq = { ...get().eq, bands, preset: "Custom" };
      if (eq.enabled) engine.setBands(bands);
      set({ eq });
      saveEq(eq);
    },

    setEqPreset: (preset) => {
      const bands = EQ_PRESETS[preset] ?? get().eq.bands;
      const eq = { ...get().eq, bands: [...bands], preset };
      if (eq.enabled) engine.setBands(eq.bands);
      set({ eq });
      saveEq(eq);
    },

    setSleepTimer: (minutes) => {
      if (sleepTimeout) clearTimeout(sleepTimeout);
      if (minutes == null) {
        set({ sleepTimerEnd: null });
        return;
      }
      const end = Date.now() + minutes * 60_000;
      set({ sleepTimerEnd: end });
      sleepTimeout = setTimeout(() => {
        engine.pause();
        set({ sleepTimerEnd: null });
      }, minutes * 60_000);
    },

    setPlayerOpen: (v) => set({ playerOpen: v }),

    dismiss: () => {
      engine.pause();
      if (currentObjectUrl) {
        URL.revokeObjectURL(currentObjectUrl);
        currentObjectUrl = null;
      }
      set({ currentId: null, isPlaying: false, playerOpen: false, currentTime: 0, duration: 0 });
    },
  };
});

