// Aurora resolver HTTP API.
//
//   GET  /health                     server + yt-dlp status
//   GET  /search?q=&limit=           YouTube search (metadata only)
//   GET  /resolve?id=                metadata for a video id
//   GET  /audio/:id                  stream audio (Range supported, cached on demand)
//   GET  /cache                      what's cached
//   DEL  /cache/:id                  drop one cached track
//   POST /prefetch                   warm the cache: {"ids":["..."]}
//
// Personal use only. See server/README.md.

import http from "node:http";
import { createReadStream } from "node:fs";
import path from "node:path";
import { config, serverInfo } from "./config.mjs";
import * as cache from "./cache.mjs";
import { search, metadata, download, version, YtDlpError } from "./ytdlp.mjs";

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const inflight = new Map(); // id -> Promise<file path>

/* ------------------------------- helpers -------------------------------- */

function send(res, status, body, headers = {}) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    ...headers,
  });
  res.end(payload);
}

function fail(res, status, message, extra = {}) {
  send(res, status, { error: message, ...extra });
}

function cors(res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-headers", "content-type,x-api-key,range");
  res.setHeader("access-control-allow-methods", "GET,POST,DELETE,OPTIONS");
  res.setHeader("access-control-expose-headers", "content-range,content-length,x-cache");
}

function authorized(req, url) {
  if (!config.apiKey) return true;
  const key = req.headers["x-api-key"] ?? url.searchParams.get("key");
  return key === config.apiKey;
}

function mimeFor(file) {
  switch (path.extname(file).toLowerCase()) {
    case ".m4a":
    case ".mp4":
      return "audio/mp4";
    case ".aac":
      return "audio/aac";
    case ".mp3":
      return "audio/mpeg";
    case ".ogg":
      return "audio/ogg";
    case ".opus":
    case ".webm":
      return "audio/webm";
    default:
      return "application/octet-stream";
  }
}

function parseRange(header, size) {
  if (!header) return null;
  const m = /^bytes=(\d*)-(\d*)$/.exec(String(header).trim());
  if (!m) return null;
  const [, rawStart, rawEnd] = m;
  if (rawStart === "" && rawEnd === "") return null;

  let start = rawStart === "" ? null : Number(rawStart);
  let end = rawEnd === "" ? null : Number(rawEnd);
  if (start === null) {
    // suffix range: last N bytes
    start = Math.max(0, size - end);
    end = size - 1;
  } else if (end === null || end >= size) {
    end = size - 1;
  }
  if (!Number.isFinite(start) || !Number.isFinite(end) || start > end || start >= size) {
    return { invalid: true };
  }
  return { start, end };
}

/** Resolve `id` to a local file, downloading on first use. */
async function ensureLocal(id) {
  const hit = await cache.find(id);
  if (hit) return { file: hit, cached: true };

  if (inflight.has(id)) return { file: await inflight.get(id), cached: false };

  const job = (async () => {
    const url = `https://www.youtube.com/watch?v=${id}`;
    const track = await metadata(url);
    const file = await download(url, config.audioDir, id);
    await cache.putMeta(id, track);
    console.log(`[cache] + ${track.artist} — ${track.title} (${id})`);
    return file;
  })().finally(() => inflight.delete(id));

  inflight.set(id, job);
  return { file: await job, cached: false };
}

async function streamFile(req, res, file, { cached }) {
  const stat = await cache.statFile(file);
  const range = parseRange(req.headers.range, stat.size);
  const base = {
    "content-type": mimeFor(file),
    "accept-ranges": "bytes",
    "cache-control": "public, max-age=86400",
    "x-cache": cached ? "hit" : "miss",
  };

  if (range?.invalid) {
    res.writeHead(416, { ...base, "content-range": `bytes */${stat.size}` });
    res.end();
    return;
  }

  if (range) {
    res.writeHead(206, {
      ...base,
      "content-range": `bytes ${range.start}-${range.end}/${stat.size}`,
      "content-length": range.end - range.start + 1,
    });
    if (req.method === "HEAD") return res.end();
    createReadStream(file, { start: range.start, end: range.end }).pipe(res);
    return;
  }

  res.writeHead(200, { ...base, "content-length": stat.size });
  if (req.method === "HEAD") return res.end();
  createReadStream(file).pipe(res);
}

/* -------------------------------- routes -------------------------------- */

async function route(req, res, url) {
  cors(res);
  if (req.method === "OPTIONS") return res.writeHead(204).end();

  const segments = url.pathname.split("/").filter(Boolean);

  if (segments[0] === "health") {
    return send(res, 200, {
      ...serverInfo,
      ok: true,
      ytdlp: await version(),
      cache: await cache.usage(),
      authRequired: Boolean(config.apiKey),
    });
  }

  if (!authorized(req, url)) return fail(res, 401, "Invalid or missing API key");

  if (segments[0] === "search") {
    const q = (url.searchParams.get("q") ?? "").trim();
    if (!q) return fail(res, 400, "Missing ?q=");
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 20), 1), 50);
    const results = await search(q, limit);
    return send(res, 200, { query: q, count: results.length, results });
  }

  if (segments[0] === "resolve") {
    const id = url.searchParams.get("id");
    if (!id) return fail(res, 400, "Missing ?id=");

    const cached = await cache.find(id);
    if (cached) {
      const m = (await cache.meta(id)) ?? { id };
      return send(res, 200, {
        ...m,
        cached: true,
        streamUrl: `/audio/${id}`,
      });
    }

    if (!VIDEO_ID.test(id)) return fail(res, 400, "Invalid video id");
    const track = await metadata(`https://www.youtube.com/watch?v=${id}`);
    await cache.putMeta(id, track);
    return send(res, 200, { ...track, cached: false, streamUrl: `/audio/${id}` });
  }

  if (segments[0] === "info" && segments[1]) {
    const id = segments[1];
    if (!VIDEO_ID.test(id)) return fail(res, 400, "Invalid video id");
    const hit = await cache.find(id);
    const m = (await cache.meta(id)) ?? null;
    if (!hit) return send(res, 200, { id, cached: false, ...m });
    const st = await cache.statFile(hit);
    return send(res, 200, {
      ...m,
      id,
      cached: true,
      bytes: st.size,
      mime: mimeFor(hit),
      cachedAt: st.mtime.toISOString(),
    });
  }

  if (segments[0] === "audio" && segments[1]) {
    const id = segments[1];
    if (!VIDEO_ID.test(id)) return fail(res, 400, "Invalid video id");
    if (req.method !== "GET" && req.method !== "HEAD") {
      return fail(res, 405, "Use GET or HEAD");
    }

    // HEAD is a probe: it must never trigger a download.
    if (req.method === "HEAD") {
      const hit = await cache.find(id);
      if (!hit) return fail(res, 404, "Not cached", { id, cached: false });
      return streamFile(req, res, hit, { cached: true });
    }

    const { file, cached } = await ensureLocal(id);
    return streamFile(req, res, file, { cached });
  }

  if (segments[0] === "cache") {
    if (req.method === "GET" && segments.length === 1) {
      return send(res, 200, {
        usage: await cache.usage(),
        items: await cache.list(),
      });
    }
    if (req.method === "DELETE" && segments[1]) {
      const removed = await cache.remove(segments[1]);
      return send(res, removed ? 200 : 404, { removed, id: segments[1] });
    }
  }

  if (segments[0] === "prefetch" && req.method === "POST") {
    const body = await readJson(req, 64 * 1024);
    const ids = Array.isArray(body?.ids) ? body.ids.filter((i) => VIDEO_ID.test(i)) : [];
    if (!ids.length) return fail(res, 400, 'Expected {"ids":["<videoId>", ...]}');

    // Fire and forget: report which ones we started.
    for (const id of ids) {
      if (inflight.has(id)) continue;
      ensureLocal(id).catch((e) => console.warn(`[prefetch] ${id}: ${e.message}`));
    }
    return send(res, 202, { queued: ids });
  }

  return fail(res, 404, `Unknown route ${url.pathname}`);
}

function readJson(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (c) => {
      size += c.length;
      if (size > limit) {
        reject(new Error("Body too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

/* --------------------------------- boot ---------------------------------- */

await cache.init();

const server = http.createServer(async (req, res) => {
  const started = Date.now();
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);

  res.on("finish", () => {
    const ms = Date.now() - started;
    if (url.pathname !== "/health") {
      console.log(`${req.method} ${url.pathname}${url.search} → ${res.statusCode} (${ms}ms)`);
    }
  });

  try {
    await route(req, res, url);
  } catch (error) {
    const status = error instanceof YtDlpError ? 502 : 500;
    console.error(`[error] ${req.method} ${url.pathname}:`, error.message);
    if (!res.headersSent) {
      fail(res, status, error.message, {
        hint:
          status === 502
            ? "Usually an expired yt-dlp. Update it with: brew upgrade yt-dlp"
            : undefined,
      });
    } else {
      res.destroy();
    }
  }
});

server.listen(config.port, config.host, async () => {
  const ytdlp = (await version()) ?? "MISSING — brew install yt-dlp";
  console.log(`aurora-resolver ${serverInfo.version} listening on http://${config.host}:${config.port}`);
  console.log(`  yt-dlp:  ${ytdlp}`);
  console.log(`  cache:   ${config.audioDir}`);
  console.log(`  auth:    ${config.apiKey ? "API key required" : "open (set AURORA_KEY to lock down)"}`);
});

// Keep the cache inside its budget, and evict in the background.
await cache.enforceLimit();
setInterval(() => cache.enforceLimit().catch(() => {}), 10 * 60_000).unref();

process.on("SIGINT", () => {
  console.log("\nbye");
  server.close(() => process.exit(0));
});
