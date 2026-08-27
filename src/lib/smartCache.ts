// Smart offline cache for direct audio that the user is allowed to download.
// YouTube and other hosted streaming services never pass through this module.

import { createStore, del, get, keys, set } from "idb-keyval";
import type { PlayStat } from "./types";

const cacheStore = createStore("aurora-cache", "audio");
const PREFIX = "c_";
const STALE_DAYS = 30;
const MAX_SINGLE_FILE_BYTES = 250 * 1024 * 1024;

interface CacheRecord {
  blob: Blob;
  size: number;
  cachedAt: number;
  lastAccess: number;
}

export interface CacheSummary {
  trackIds: string[];
  bytes: number;
}

function isBrowserWithIDB(): boolean {
  return typeof window !== "undefined" && typeof indexedDB !== "undefined";
}

function toRecord(value: unknown): CacheRecord | null {
  // Migrate blobs written by older Aurora builds without downloading them again.
  if (value instanceof Blob) {
    return { blob: value, size: value.size, cachedAt: 0, lastAccess: 0 };
  }
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<CacheRecord>;
  if (!(candidate.blob instanceof Blob)) return null;
  return {
    blob: candidate.blob,
    size: candidate.size ?? candidate.blob.size,
    cachedAt: candidate.cachedAt ?? 0,
    lastAccess: candidate.lastAccess ?? 0,
  };
}

async function getRecords(): Promise<Array<{ id: string; record: CacheRecord }>> {
  const allKeys = (await keys(cacheStore)) as string[];
  const records = await Promise.all(
    allKeys
      .filter((key) => key.startsWith(PREFIX))
      .map(async (key) => {
        const record = toRecord(await get<unknown>(key, cacheStore));
        return record ? { id: key.slice(PREFIX.length), record } : null;
      }),
  );
  return records.filter((entry): entry is { id: string; record: CacheRecord } => entry !== null);
}

export async function getCacheSummary(): Promise<CacheSummary> {
  if (!isBrowserWithIDB()) return { trackIds: [], bytes: 0 };
  try {
    const records = await getRecords();
    return {
      trackIds: records.map(({ id }) => id),
      bytes: records.reduce((total, { record }) => total + record.size, 0),
    };
  } catch {
    return { trackIds: [], bytes: 0 };
  }
}

/** Returns the IDs of all direct-audio tracks stored in the offline cache. */
export async function getCachedTrackIds(): Promise<string[]> {
  return (await getCacheSummary()).trackIds;
}

/** Retrieve cached audio and mark it as recently used. */
export async function getCachedBlob(id: string): Promise<Blob | undefined> {
  if (!isBrowserWithIDB()) return undefined;
  try {
    const key = `${PREFIX}${id}`;
    const record = toRecord(await get<unknown>(key, cacheStore));
    if (!record) return undefined;
    void set(key, { ...record, lastAccess: Date.now() }, cacheStore);
    return record.blob;
  } catch {
    return undefined;
  }
}

export async function removeCachedBlob(id: string): Promise<void> {
  if (!isBrowserWithIDB()) return;
  try {
    await del(`${PREFIX}${id}`, cacheStore);
  } catch {
    /* ignore storage errors */
  }
}

export async function clearCacheStore(): Promise<void> {
  if (!isBrowserWithIDB()) return;
  try {
    const { trackIds } = await getCacheSummary();
    await Promise.all(trackIds.map((id) => removeCachedBlob(id)));
  } catch {
    /* ignore storage errors */
  }
}

function trackScore(stat: PlayStat | undefined, record: CacheRecord): number {
  if (!stat || stat.count === 0) return record.lastAccess > 0 ? 0.01 : 0;
  const daysSince = (Date.now() - stat.lastPlayed) / 86_400_000;
  if (daysSince > STALE_DAYS) return 0;
  return stat.count / Math.max(1, daysSince);
}

async function evictToLimit(
  stats: Record<string, PlayStat>,
  maxBytes: number,
  protectedId: string,
): Promise<void> {
  const records = await getRecords();
  let total = records.reduce((sum, { record }) => sum + record.size, 0);
  if (total <= maxBytes) return;

  const candidates = records
    .filter(({ id }) => id !== protectedId)
    .map(({ id, record }) => ({
      id,
      size: record.size,
      score: trackScore(stats[id], record),
      lastAccess: record.lastAccess,
    }))
    .sort((a, b) => a.score - b.score || a.lastAccess - b.lastAccess);

  for (const candidate of candidates) {
    if (total <= maxBytes) break;
    await removeCachedBlob(candidate.id);
    total -= candidate.size;
  }
}

/**
 * Download one explicitly eligible direct-audio URL into Aurora's cache.
 * The caller is responsible for checking the track's `downloadAllowed` flag.
 */
export async function cacheUrlTrack(
  id: string,
  url: string,
  stats: Record<string, PlayStat>,
  maxBytes: number,
): Promise<string[]> {
  if (!isBrowserWithIDB() || maxBytes <= 0) return [];
  try {
    const existing = toRecord(await get<unknown>(`${PREFIX}${id}`, cacheStore));
    if (existing) return getCachedTrackIds();

    const response = await fetch(url, { credentials: "omit" });
    if (!response.ok) return getCachedTrackIds();

    const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
    if (contentType && !contentType.startsWith("audio/") && !contentType.includes("octet-stream")) {
      return getCachedTrackIds();
    }

    const blob = await response.blob();
    if (blob.size === 0 || blob.size > Math.min(maxBytes, MAX_SINGLE_FILE_BYTES)) {
      return getCachedTrackIds();
    }

    const now = Date.now();
    await set(
      `${PREFIX}${id}`,
      { blob, size: blob.size, cachedAt: now, lastAccess: now } satisfies CacheRecord,
      cacheStore,
    );
    await evictToLimit(stats, maxBytes, id);
    return getCachedTrackIds();
  } catch {
    return getCachedTrackIds();
  }
}
