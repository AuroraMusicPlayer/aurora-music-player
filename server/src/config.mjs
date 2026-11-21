import path from "node:path";
import os from "node:os";

const dataDir = process.env.AURORA_DATA ?? path.join(process.cwd(), "data");

export const config = {
  host: process.env.AURORA_HOST ?? "0.0.0.0",
  port: Number(process.env.AURORA_PORT ?? 8787),

  // Optional shared secret. Strongly recommended when the phone reaches this
  // server over Wi-Fi or a tunnel. Sent as "x-api-key" or "?key=".
  apiKey: process.env.AURORA_KEY ?? "",

  // If YouTube starts answering "Sign in to confirm you're not a bot", point
  // this at a browser you're logged into (chrome, safari, firefox, edge, brave).
  // yt-dlp borrows its cookies so requests look like a normal session.
  cookiesBrowser: process.env.AURORA_COOKIES_BROWSER ?? "",

  dataDir,
  audioDir: path.join(dataDir, "audio"),
  metaDir: path.join(dataDir, "meta"),

  // Oldest tracks are evicted once the cache exceeds this.
  maxCacheBytes: Number(process.env.AURORA_MAX_CACHE_GB ?? 20) * 1024 ** 3,

  ytdlp: process.env.AURORA_YTDLP ?? "yt-dlp",

  // iOS can't play Opus-in-WebM, so everything is normalised to m4a/AAC.
  audioFormat: "m4a",

  resolveTimeoutMs: 45_000,
  searchTimeoutMs: 30_000,
  downloadTimeoutMs: 5 * 60_000,
};

export const serverInfo = {
  name: "aurora-resolver",
  version: "0.1.0",
  platform: `${os.platform()} ${os.arch()}`,
};
