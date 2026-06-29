// IndexedDB persistence (via idb-keyval) for Aurora Music.
// We keep three stores:
//   - meta:  the serialisable library state (tracks/playlists/stats/favorites/queue)
//   - blobs: the raw File/Blob for each local track, keyed by track id
// All access is client-only; callers must guard against SSR.

import { get, set, del, clear, createStore } from "idb-keyval";
import type { Track, Playlist, PlayStat } from "./types";

const metaStore = createStore("aurora-meta", "kv");
const blobStore = createStore("aurora-blobs", "kv");

export interface PersistedLibrary {
  tracks: Track[];
  playlists: Playlist[];
  favorites: string[];
  stats: Record<string, PlayStat>;
  queue: string[];
  queueIndex: number;
}

const LIB_KEY = "library";

export function isBrowser() {
  return typeof window !== "undefined" && typeof indexedDB !== "undefined";
}

export async function loadLibrary(): Promise<PersistedLibrary | null> {
  if (!isBrowser()) return null;
  try {
    const data = await get<PersistedLibrary>(LIB_KEY, metaStore);
    return data ?? null;
  } catch {
    return null;
  }
}

export async function saveLibrary(lib: PersistedLibrary): Promise<void> {
  if (!isBrowser()) return;
  // Strip runtime-only fields (artwork object URLs) before persisting.
  const tracks = lib.tracks.map((t) => ({ ...t, artwork: null }));
  await set(LIB_KEY, { ...lib, tracks }, metaStore);
}

export async function putBlob(id: string, blob: Blob): Promise<void> {
  if (!isBrowser()) return;
  await set(id, blob, blobStore);
}

export async function getBlob(id: string): Promise<Blob | undefined> {
  if (!isBrowser()) return undefined;
  return get<Blob>(id, blobStore);
}

export async function deleteBlob(id: string): Promise<void> {
  if (!isBrowser()) return;
  await del(id, blobStore);
}

export async function clearAll(): Promise<void> {
  if (!isBrowser()) return;
  await Promise.all([clear(metaStore), clear(blobStore)]);
}
