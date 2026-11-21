// On-disk audio cache. The filesystem is the source of truth, so the cache
// survives restarts and can be inspected with Finder / `ls`.
//
//   data/audio/<videoId>.m4a    audio, ready to stream or copy to a phone
//   data/meta/<videoId>.json    track metadata next to the audio

import fs from "node:fs/promises";
import path from "node:path";
import { config } from "./config.mjs";

const AUDIO_EXT = new Set(["m4a", "mp4", "aac", "opus", "webm", "mp3", "ogg"]);

export async function init() {
  await fs.mkdir(config.audioDir, { recursive: true });
  await fs.mkdir(config.metaDir, { recursive: true });
}

function audioPath(id, ext = config.audioFormat) {
  return path.join(config.audioDir, `${id}.${ext}`);
}

function metaPath(id) {
  return path.join(config.metaDir, `${id}.json`);
}

/** Returns the audio file path if `id` is fully cached, otherwise null. */
export async function find(id) {
  let names;
  try {
    names = await fs.readdir(config.audioDir);
  } catch {
    return null;
  }
  const hit = names.find((n) => n.startsWith(`${id}.`));
  if (!hit) return null;
  const ext = hit.split(".").pop().toLowerCase();
  if (!AUDIO_EXT.has(ext)) return null;

  const full = path.join(config.audioDir, hit);
  const stat = await fs.stat(full).catch(() => null);
  // A truncated/partial file is worse than a miss: treat tiny files as absent.
  if (!stat || stat.size < 1024) return null;
  return full;
}

export async function meta(id) {
  try {
    return JSON.parse(await fs.readFile(metaPath(id), "utf8"));
  } catch {
    return null;
  }
}

export async function putMeta(id, track) {
  await fs.writeFile(metaPath(id), JSON.stringify(track, null, 2));
}

export async function remove(id) {
  const file = await find(id);
  if (file) await fs.rm(file, { force: true });
  await fs.rm(metaPath(id), { force: true });
  return Boolean(file);
}

export async function statFile(file) {
  return fs.stat(file);
}

/** Cached tracks, newest first. */
export async function list() {
  let names;
  try {
    names = await fs.readdir(config.audioDir);
  } catch {
    return [];
  }

  const out = [];
  for (const name of names) {
    const ext = name.split(".").pop().toLowerCase();
    if (!AUDIO_EXT.has(ext)) continue;
    const id = name.slice(0, -(ext.length + 1));
    const full = path.join(config.audioDir, name);
    const st = await fs.stat(full).catch(() => null);
    if (!st || st.size < 1024) continue;

    const m = await meta(id);
    out.push({
      id,
      title: m?.title ?? id,
      artist: m?.artist ?? "Unknown artist",
      album: m?.album ?? null,
      duration: m?.duration ?? null,
      thumbnail: m?.thumbnail ?? null,
      bytes: st.size,
      cachedAt: st.mtime.toISOString(),
    });
  }
  return out.sort((a, b) => b.cachedAt.localeCompare(a.cachedAt));
}

export async function usage() {
  const items = await list();
  return {
    count: items.length,
    bytes: items.reduce((n, i) => n + i.bytes, 0),
    limitBytes: config.maxCacheBytes,
  };
}

/** Evict oldest tracks until the cache fits the budget. */
export async function enforceLimit() {
  const items = await list(); // newest first
  let total = items.reduce((n, i) => n + i.bytes, 0);
  const evicted = [];

  for (let i = items.length - 1; i >= 0 && total > config.maxCacheBytes; i--) {
    const item = items[i];
    await remove(item.id);
    total -= item.bytes;
    evicted.push(item.id);
  }
  return evicted;
}

export { audioPath, metaPath };
