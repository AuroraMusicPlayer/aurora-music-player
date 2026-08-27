// Core domain types for Aurora Music.

export type RepeatMode = "off" | "all" | "one";

export type ThemeMode = "light" | "dark" | "amoled" | "system";

/** Where a track's audio data comes from. */
export type TrackSource = "local" | "url";

export type OnlineProvider = "youtube";

export interface OnlineTrack {
  id: string;
  videoId: string;
  title: string;
  artist: string;
  artwork: string;
  provider: OnlineProvider;
  addedAt: number;
}

export interface OnlinePlaylist {
  id: string;
  name: string;
  videoIds: string[];
  createdAt: number;
}

export interface Track {
  id: string;
  title: string;
  artist: string;
  album: string;
  albumArtist: string;
  genre: string;
  year: number | null;
  /** Duration in seconds (0 until known). */
  duration: number;
  trackNo: number | null;
  /** Virtual folder path (for local files derived from relative path). */
  folder: string;
  source: TrackSource;
  /** For url tracks: the streamable URL. For local: empty (blob lives in IDB). */
  url: string;
  /** User confirmed this direct-audio source may be stored for offline use. */
  downloadAllowed?: boolean;
  /** Object URL for embedded/derived artwork, created at runtime. */
  artwork: string | null;
  /** Embedded lyrics if present. */
  lyrics: string | null;
  /** ms timestamp added. */
  addedAt: number;
  fileName: string;
}

export interface Playlist {
  id: string;
  name: string;
  trackIds: string[];
  createdAt: number;
  /** System playlists are auto-generated and not editable. */
  system?: boolean;
}

export interface PlayStat {
  count: number;
  lastPlayed: number;
}

export interface EqualizerState {
  enabled: boolean;
  /** Gain in dB for each of the 10 bands. */
  bands: number[];
  preset: string;
}

export const EQ_FREQUENCIES = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

export const EQ_PRESETS: Record<string, number[]> = {
  Flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  "Bass Boost": [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
  Treble: [0, 0, 0, 0, 0, 1, 3, 5, 6, 7],
  Vocal: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
  Rock: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5],
  Pop: [-1, 1, 3, 4, 4, 2, 0, -1, -1, -1],
  Jazz: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  Electronic: [5, 4, 1, 0, -2, 1, 1, 3, 4, 5],
};

export const ACCENT_PRESETS: { name: string; value: string; strong: string }[] = [
  { name: "Aurora", value: "oklch(0.74 0.15 195)", strong: "oklch(0.68 0.17 200)" },
  { name: "Violet", value: "oklch(0.66 0.2 300)", strong: "oklch(0.6 0.22 300)" },
  { name: "Sunset", value: "oklch(0.72 0.19 35)", strong: "oklch(0.66 0.21 30)" },
  { name: "Lime", value: "oklch(0.82 0.2 135)", strong: "oklch(0.76 0.22 138)" },
  { name: "Rose", value: "oklch(0.7 0.2 0)", strong: "oklch(0.64 0.22 360)" },
  { name: "Gold", value: "oklch(0.82 0.16 85)", strong: "oklch(0.76 0.17 80)" },
  { name: "Ocean", value: "oklch(0.66 0.16 245)", strong: "oklch(0.6 0.18 250)" },
];
