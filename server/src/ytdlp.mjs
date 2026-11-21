// Thin, dependency-free wrapper around the yt-dlp binary.
// All calls use an argv array (never a shell string) so video ids and search
// terms can't be interpreted by a shell.

import { spawn } from "node:child_process";
import { config } from "./config.mjs";

class YtDlpError extends Error {
  constructor(message, { code, stderr } = {}) {
    super(message);
    this.name = "YtDlpError";
    this.code = code;
    this.stderr = stderr;
  }
}

function run(args, { timeoutMs = config.resolveTimeoutMs } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(config.ytdlp, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });

    const out = [];
    const err = [];
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill("SIGKILL");
      reject(new YtDlpError(`yt-dlp timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.on("data", (c) => out.push(c));
    child.stderr.on("data", (c) => err.push(c));

    child.on("error", (e) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(
        new YtDlpError(
          e.code === "ENOENT"
            ? "yt-dlp is not installed or not on PATH (brew install yt-dlp)"
            : e.message,
        ),
      );
    });

    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const stderr = Buffer.concat(err).toString("utf8").trim();
      if (code !== 0) {
        reject(
          new YtDlpError(`yt-dlp exited with code ${code}`, { code, stderr }),
        );
        return;
      }
      resolve({ stdout: Buffer.concat(out).toString("utf8"), stderr });
    });
  });
}

// "(Official Video)", "[Lyric Video]", "(HD)", "(Remastered 2011)" and friends
// carry no meaning in a music library and make search results noisy.
const NOISE = /[([{]\s*(?:official\s*(?:music\s*)?(?:video|audio|visuali[sz]er)|lyric\s*video|lyrics?|audio|hd|hq|4k|mv|m\/v|8d|remaster(?:ed)?(?:\s*\d{4})?|explicit|clean|full\s*album|prod\.?\s*by[^)\]}]*)\s*[)\]}]/gi;
const NOISE_TAIL = /\s*[-–—|]\s*(?:official\s*(?:music\s*)?(?:video|audio)|lyric\s*video|lyrics)\s*$/i;

function cleanTitle(rawTitle, artist) {
  let title = String(rawTitle).replace(NOISE, " ").replace(NOISE_TAIL, "");

  // "Daft Punk - Instant Crush" → "Instant Crush" when the artist is known.
  if (artist) {
    const bare = artist.replace(/\s*-\s*Topic$/i, "");
    const prefix = new RegExp(`^\\s*${escapeRegExp(bare)}\\s*[-–—]\\s*`, "i");
    if (prefix.test(title)) title = title.replace(prefix, "");
  }

  return title.replace(/\s{2,}/g, " ").replace(/[\s\-–—|]+$/, "").trim() || String(rawTitle);
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Cookies, when configured, so YouTube treats the resolver like a real session. */
function sessionArgs() {
  return config.cookiesBrowser
    ? ["--cookies-from-browser", config.cookiesBrowser]
    : [];
}

/** Turn a yt-dlp entry into the shape the app expects. */
function toTrack(entry) {
  if (!entry?.id) return null;
  const thumbs = Array.isArray(entry.thumbnails) ? entry.thumbnails : [];
  const bestThumb = thumbs.length
    ? [...thumbs].sort((a, b) => (b.width ?? 0) - (a.width ?? 0))[0]?.url
    : entry.thumbnail;

  const artist =
    entry.artist ??
    entry.creator ??
    entry.channel ??
    entry.uploader ??
    "Unknown artist";

  const rawTitle = entry.track ?? entry.title ?? "Unknown title";
  const cleanArtist = String(artist).replace(/ - Topic$/i, "").trim();

  return {
    id: entry.id,
    title: cleanTitle(rawTitle, cleanArtist),
    artist: cleanArtist || "Unknown artist",
    rawTitle: entry.title ?? null,
    album: entry.album ?? null,
    duration: Number.isFinite(entry.duration) ? Math.round(entry.duration) : null,
    thumbnail: bestThumb ?? `https://i.ytimg.com/vi/${entry.id}/hqdefault.jpg`,
    webpageUrl: entry.webpage_url ?? `https://www.youtube.com/watch?v=${entry.id}`,
    uploadDate: entry.upload_date ?? null,
  };
}

export async function search(query, limit = 20) {
  const { stdout } = await run(
    [
      ...sessionArgs(),
      "--flat-playlist",
      "--dump-single-json",
      "--no-warnings",
      "--no-playlist",
      "--socket-timeout",
      "20",
      `ytsearch${limit}:${query}`,
    ],
    { timeoutMs: config.searchTimeoutMs },
  );

  const parsed = JSON.parse(stdout);
  const entries = Array.isArray(parsed?.entries) ? parsed.entries : [];

  // YouTube happily returns the same upload several times; keep the first.
  const seen = new Set();
  const tracks = [];
  for (const entry of entries) {
    const track = toTrack(entry);
    if (!track) continue;
    const key = `${track.title.toLowerCase()}|${track.artist.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    tracks.push(track);
  }
  return tracks;
}

/** Metadata only — used when the user pastes a link or opens a track. */
export async function metadata(url) {
  const { stdout } = await run([
    ...sessionArgs(),
    "--dump-single-json",
    "--no-warnings",
    "--no-playlist",
    "--skip-download",
    "--socket-timeout",
    "20",
    "-f",
    "bestaudio/best",
    url,
  ]);

  const track = toTrack(JSON.parse(stdout));
  if (!track) throw new YtDlpError("No playable stream found for that URL");
  return track;
}

/**
 * Download the best audio track, normalised to m4a, into `dir`.
 * Returns the resulting file path.
 */
export async function download(url, dir, id) {
  await run(
    [
      ...sessionArgs(),
      "--no-warnings",
      "--no-playlist",
      "--no-progress",
      "--socket-timeout",
      "30",
      "--retries",
      "3",
      "-f",
      "bestaudio[ext=m4a]/bestaudio/best",
      "-x",
      "--audio-format",
      config.audioFormat,
      "--audio-quality",
      "0",
      "--force-overwrites",
      "-o",
      `${dir}/${id}.%(ext)s`,
      url,
    ],
    { timeoutMs: config.downloadTimeoutMs },
  );

  return `${dir}/${id}.${config.audioFormat}`;
}

export async function version() {
  try {
    const { stdout } = await run(["--version"], { timeoutMs: 10_000 });
    return stdout.trim();
  } catch {
    return null;
  }
}

export { YtDlpError, toTrack };
