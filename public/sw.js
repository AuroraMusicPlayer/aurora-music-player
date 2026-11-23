/*
 * Aurora Music service worker.
 *
 * Goal: the app opens and works offline once installed, and is served from the
 * cache on a flaky connection instead of showing the browser's error page.
 *
 * Deliberately conservative:
 *  - only same-origin GET requests are touched
 *  - navigations are network-first, so a deployed update is seen immediately
 *  - static assets are cache-first, which is what makes it fast
 *  - audio files are never cached: they are huge, and the player has its own
 *    cache with a budget
 */

const VERSION = "aurora-v1";
const SHELL = `${VERSION}-shell`;
const ASSETS = `${VERSION}-assets`;

const SHELL_URLS = [
  "/",
  "/manifest.webmanifest",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-maskable.png",
  "/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL);
      // Individually, so one 404 cannot fail the whole install.
      await Promise.all(
        SHELL_URLS.map(async (url) => {
          try {
            const response = await fetch(url, { cache: "reload" });
            if (response.ok) await cache.put(url, response.clone());
          } catch {
            /* offline during install: skip this entry */
          }
        }),
      );
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => !key.startsWith(VERSION))
          .map((key) => caches.delete(key)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/api/")) return;

  // Audio should go straight to the network / the player's own cache.
  if (/\.(mp3|m4a|aac|flac|ogg|opus|wav|mp4)$/i.test(url.pathname)) return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirst(request));
    return;
  }

  event.respondWith(cacheFirst(request));
});

async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(SHELL);
      cache.put("/", response.clone());
    }
    return response;
  } catch {
    const cached = (await caches.match(request)) || (await caches.match("/"));
    if (cached) return cached;
    return new Response(
      "<!doctype html><meta name=viewport content='width=device-width'>" +
        "<body style='background:#030303;color:#fff;font-family:system-ui;display:grid;place-items:center;height:100vh;margin:0'>" +
        "<div style='text-align:center'><h1 style='font-size:20px'>Aurora Music</h1>" +
        "<p style='color:#888;font-size:14px'>You are offline and the app has not been cached yet.<br>Reconnect once and it will open offline afterwards.</p></div>",
      { headers: { "Content-Type": "text/html; charset=utf-8" } },
    );
  }
}

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(ASSETS);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    return new Response("", { status: 504 });
  }
}
