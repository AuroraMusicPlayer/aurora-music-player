// Smart offline caching for Aurora Music.
// Automatically fetches and caches audio blobs for URL-source tracks in IndexedDB.
// Intelligently evicts the least-listened tracks when the cache limit is reached.

import { get, set, del, keys, createStore } from "idb-keyval";
import type { PlayStat } from "./types";

const cacheStore = createStore("aurora-cache", "audio");

/** Maximum number of URL tracks to keep cached. */
const MAX_CACHED = 50;
/** Tracks not played within this many days are candidates for eviction. */
const STALE_DAYS = 30;
/** IDB key prefix so cached blobs never collide with other stores. */
const PREFIX = "c_";

function isBrowserWithIDB(): boolean {
  return typeof window !== "undefined" && typeof indexedDB !== "undefined";
}

/** Returns the IDs of all URL tracks currently stored in the smart cache. */
export async function getCachedTrackIds(): Promise<string[]> {
  if (!isBrowserWithIDB()) return [];
  try {
    const allKeys = (await keys(cacheStore)) as string[];
    return allKeys.filter((k) => k.startsWith(PREFIX)).map((k) => k.slice(PREFIX.length));
  } catch {
    return [];
  }
}

/** Retrieve the cached audio blob for a URL track, if any. */
export async function getCachedBlob(id: string): Promise<Blob | undefined> {
  if (!isBrowserWithIDB()) return undefined;
  try {
    return await get<Blob>(`${PREFIX}${id}`, cacheStore);
  } catch {
    return undefined;
  }
}

/** Remove a single cached blob (e.g. when the track is deleted from the library). */
export async function removeCachedBlob(id: string): Promise<void> {
  if (!isBrowserWithIDB()) return;
  try {
    await del(`${PREFIX}${id}`, cacheStore);
  } catch {
    /* ignore */
  }
}

/** Wipe all cached audio blobs. */
export async function clearCacheStore(): Promise<void> {
  if (!isBrowserWithIDB()) return;
  try {
    const ids = await getCachedTrackIds();
    await Promise.all(ids.map((id) => removeCachedBlob(id)));
  } catch {
    /* ignore */
  }
}

function trackScore(stat: PlayStat | undefined): number {
  if (!stat || stat.count === 0) return 0;
  const daysSince = (Date.now() - stat.lastPlayed) / 86_400_000;
  if (daysSince > STALE_DAYS) return 0;
  return stat.count / Math.max(1, daysSince);
}

async function evictIfNeeded(
  stats: Record<string, PlayStat>,
  cachedIds: string[],
): Promise<void> {
  if (cachedIds.length <= MAX_CACHED) return;
  const scored = cachedIds
    .map((id) => ({ id, score: trackScore(stats[id]) }))
    .sort((a, b) => a.score - b.score);
  const excess = cachedIds.length - MAX_CACHED;
  await Promise.all(scored.slice(0, excess).map((e) => removeCachedBlob(e.id)));
}

/**
 * Background-fetch and cache a URL-source track's audio blob.
 * Safe to fire-and-forget — errors are swallowed silently.
 * Returns the updated list of cached track IDs after the operation.
 */
export async function cacheUrlTrack(
  id: string,
  url: string,
  stats: Record<string, PlayStat>,
): Promise<string[]> {
  if (!isBrowserWithIDB()) return [];
  try {
    // Skip if already cached.
    const existing = await get<Blob>(`${PREFIX}${id}`, cacheStore);
    if (existing) return getCachedTrackIds();

    const response = await fetch(url, { credentials: "omit" });
    if (!response.ok) return getCachedTrackIds();

    const blob = await response.blob();
    // Skip blobs that are too large (>50 MB) to avoid exhausting storage quota.
    const MAX_BLOB_BYTES = 50 * 1024 * 1024;
    if (blob.size > MAX_BLOB_BYTES) return getCachedTrackIds();
    await set(`${PREFIX}${id}`, blob, cacheStore);

    const allIds = await getCachedTrackIds();
    await evictIfNeeded(stats, allIds);
    return getCachedTrackIds();
  } catch {
    return getCachedTrackIds();
  }
}
