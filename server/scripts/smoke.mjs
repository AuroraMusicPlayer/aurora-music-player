// End-to-end smoke test against a running resolver.
//
//   node scripts/smoke.mjs "https://localhost:8787" "$AURORA_KEY"
//
// Exercises: health → search → full download → Range seek → cache listing.

const base = (process.argv[2] ?? "http://localhost:8787").replace(/\/$/, "");
const key = process.argv[3] ?? process.env.AURORA_KEY ?? "";
const headers = key ? { "x-api-key": key } : {};

function ok(label, condition, detail = "") {
  console.log(`${condition ? "PASS" : "FAIL"}  ${label}${detail ? ` — ${detail}` : ""}`);
  if (!condition) process.exitCode = 1;
  return condition;
}

const health = await (await fetch(`${base}/health`)).json();
ok("health", health.ok === true);
if (!health.ytdlp) {
  console.error("yt-dlp is not available on the resolver; aborting.");
  process.exit(1);
}
console.log(`      yt-dlp ${health.ytdlp}`);

const search = await (await fetch(`${base}/search?q=daft+punk&limit=5`, { headers })).json();
ok("search returns results", Array.isArray(search.results) && search.results.length > 0,
  `${search.results?.length ?? 0} results`);
if (!search.results?.length) process.exit(1);

for (const track of search.results.slice(0, 5)) {
  console.log(`      ${track.id}  ${track.artist} — ${track.title}`);
}

const track = search.results[0];
const audio = await fetch(`${base}/audio/${track.id}`, { headers });
ok("audio downloads", audio.ok, `${audio.status} ${audio.headers.get("content-type")} ${audio.headers.get("x-cache")}`);

const bytes = (await audio.arrayBuffer()).byteLength;
ok("audio is non-trivial", bytes > 100_000, `${bytes} bytes`);

const ranged = await fetch(`${base}/audio/${track.id}`, {
  headers: { ...headers, range: "bytes=0-1023" },
});
ok("range request", ranged.status === 206, `${ranged.status} ${ranged.headers.get("content-range")}`);
await ranged.arrayBuffer();

const listed = await (await fetch(`${base}/cache`, { headers })).json();
ok("cache lists the track", listed.items.some((i) => i.id === track.id), `${listed.items.length} cached`);
ok("cache byte count matches", listed.items.find((i) => i.id === track.id)?.bytes === bytes);

const second = await fetch(`${base}/audio/${track.id}`, { headers });
ok("second request is a cache hit", second.headers.get("x-cache") === "hit");
await second.arrayBuffer();

console.log(process.exitCode ? "\nsmoke test FAILED" : "\nsmoke test passed");
