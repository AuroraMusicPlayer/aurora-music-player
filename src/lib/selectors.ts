// Pure helpers that derive grouped collections from the flat track list.

import type { PlayStat, Track } from "./types";

export function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export interface Album {
  id: string;
  name: string;
  artist: string;
  artwork: string | null;
  trackIds: string[];
  year: number | null;
}

export interface Collection {
  id: string;
  name: string;
  artwork: string | null;
  trackIds: string[];
  subtitle: string;
}

function firstArt(tracks: Track[]): string | null {
  return tracks.find((t) => t.artwork)?.artwork ?? null;
}

export function getAlbums(tracks: Track[]): Album[] {
  const map = new Map<string, Track[]>();
  for (const t of tracks) {
    const key = `${t.album}\u0000${t.albumArtist}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(t);
  }
  return [...map.entries()]
    .map(([key, ts]) => {
      const [name, artist] = key.split("\u0000");
      const sorted = [...ts].sort((a, b) => (a.trackNo ?? 0) - (b.trackNo ?? 0));
      return {
        id: encodeURIComponent(key),
        name,
        artist,
        artwork: firstArt(ts),
        trackIds: sorted.map((t) => t.id),
        year: ts.find((t) => t.year)?.year ?? null,
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

function groupBy(tracks: Track[], field: (t: Track) => string): Collection[] {
  const map = new Map<string, Track[]>();
  for (const t of tracks) {
    const key = field(t);
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(t);
  }
  return [...map.entries()]
    .map(([name, ts]) => ({
      id: encodeURIComponent(name),
      name,
      artwork: firstArt(ts),
      trackIds: ts.map((t) => t.id),
      subtitle: `${ts.length} song${ts.length === 1 ? "" : "s"}`,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export const getArtists = (t: Track[]) => groupBy(t, (x) => x.artist);
export const getGenres = (t: Track[]) => groupBy(t, (x) => x.genre);
export const getFolders = (t: Track[]) => groupBy(t, (x) => x.folder);
export const getYears = (t: Track[]) =>
  groupBy(t, (x) => (x.year ? String(x.year) : "Unknown")).sort((a, b) =>
    b.name.localeCompare(a.name),
  );

export function recentlyPlayed(tracks: Track[], stats: Record<string, PlayStat>): Track[] {
  return tracks
    .filter((t) => stats[t.id]?.lastPlayed)
    .sort((a, b) => (stats[b.id]?.lastPlayed ?? 0) - (stats[a.id]?.lastPlayed ?? 0));
}

export function mostPlayed(tracks: Track[], stats: Record<string, PlayStat>): Track[] {
  return tracks
    .filter((t) => (stats[t.id]?.count ?? 0) > 0)
    .sort((a, b) => (stats[b.id]?.count ?? 0) - (stats[a.id]?.count ?? 0));
}

export function recentlyAdded(tracks: Track[]): Track[] {
  return [...tracks].sort((a, b) => b.addedAt - a.addedAt);
}

export function searchTracks(tracks: Track[], q: string): Track[] {
  const query = q.trim().toLowerCase();
  if (!query) return [];
  return tracks.filter((t) =>
    [t.title, t.artist, t.album, t.genre, t.folder].some((f) =>
      f.toLowerCase().includes(query),
    ),
  );
}

export function byIds(tracks: Track[], ids: string[]): Track[] {
  const map = new Map(tracks.map((t) => [t.id, t]));
  return ids.map((id) => map.get(id)).filter((t): t is Track => Boolean(t));
}
