# Aurora resolver

Local service that turns YouTube links into cacheable audio files for the
Aurora Music app. **Personal use only** — it downloads content that YouTube's
Terms of Service don't permit third-party apps to download, so it is not
distribution-safe and must not be shared or sold.

## Why a separate service

Extracting audio inside the mobile app is fragile: YouTube rotates its player
signature/PO-token requirements every few weeks, and every fix would mean
shipping a new APK/IPA. Keeping extraction in one `yt-dlp` process means a
single `brew upgrade yt-dlp` fixes the whole app.

It also gives you a real offline cache: download once on the server, then the
phone can stream or pull the file while on Wi-Fi.

## Requirements

- Node 20+
- `yt-dlp` (`brew install yt-dlp`)
- `ffmpeg` (`brew install ffmpeg`) — only needed for transcoding, but keep it handy

## Run

```sh
cd server
AURORA_KEY="pick-a-secret" npm start
```

Open <http://localhost:8787/health> to confirm `ytdlp` reports a version.

### Configuration

| Env | Default | Meaning |
| --- | --- | --- |
| `AURORA_PORT` | `8787` | HTTP port |
| `AURORA_HOST` | `0.0.0.0` | Bind address (0.0.0.0 so the phone can reach it) |
| `AURORA_KEY` | *(empty)* | Shared secret, sent as `x-api-key` or `?key=`. Set it. |
| `AURORA_DATA` | `./data` | Cache location |
| `AURORA_MAX_CACHE_GB` | `20` | Oldest tracks are evicted past this |
| `AURORA_YTDLP` | `yt-dlp` | Path to the binary |
| `AURORA_COOKIES_BROWSER` | *(empty)* | `chrome`, `safari`, `firefox`, `edge`, `brave` — borrow that browser's YouTube cookies to dodge "confirm you're not a bot" |

## API

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/health` | Status, yt-dlp version, cache usage |
| `GET` | `/search?q=&limit=` | YouTube search, metadata only |
| `GET` | `/resolve?id=` | Track metadata for an 11-char video id |
| `GET` | `/info/:id` | `{cached, bytes, mime}` — safe to call often, never downloads |
| `GET` | `/audio/:id` | Audio stream. `Range` supported, downloads on first hit |
| `HEAD` | `/audio/:id` | Probe only: `200` if cached, `404` if not. Never starts a download |
| `GET` | `/cache` | Cached tracks + total size |
| `DELETE` | `/cache/:id` | Remove one cached track |
| `POST` | `/prefetch` | `{"ids":["dQw4w9WgXcQ"]}` — start downloads early |

Example:

```sh
curl -s "http://localhost:8787/search?q=daft+punk+instant+crush" -H "x-api-key: $AURORA_KEY" | jq '.results[0]'
curl -s -o track.m4a "http://localhost:8787/audio/dQw4w9WgXcQ" -H "x-api-key: $AURORA_KEY"
```

## Reaching it from the phone

- **Same Wi-Fi:** `http://<your-mac>.local:8787`
- **Away from home:** run [Tailscale](https://tailscale.com) on the Mac and the
  phone. Do **not** port-forward this to the public internet — it is not
  hardened for that.

## Failure modes and fixes

| Symptom | Fix |
| --- | --- |
| `502 … expired yt-dlp` | `brew upgrade yt-dlp` |
| `Sign in to confirm you're not a bot` | `AURORA_COOKIES_BROWSER=chrome npm start` (the browser must be logged into YouTube) |
| Track downloads as `.webm`/opus and iOS won't play it | Ensure `ffmpeg` is on `PATH`; the `--audio-format m4a` step needs it |
| Slow first play | Use `POST /prefetch` for the next few queue items |
