# Aurora Music — YouTube + offline + car integration

Personal-use build. Not for the App Store or Play Store, not for sharing.

This document is the plan of record for turning the current web player
(`src/`, React + TanStack Start) into real phone apps that play YouTube audio,
cache it locally, and appear in Android Auto and CarPlay.

---

## 1. What we're building

| Piece | Status |
| --- | --- |
| `server/` — local YouTube resolver + audio cache | **built** (this change) |
| `mobile/` — Flutter app (Android + iOS) | next |
| Android Auto integration | planned, Phase 4 |
| CarPlay integration | planned, Phase 5 |
| Offline playback | Phase 3 |

The existing React app stays as the web/PWA player. It can point at the same
resolver later, but it can never satisfy the car requirement — Android Auto and
CarPlay need native app code, not a web wrapper.

## 2. Architecture

Everything runs on the phone. No server, no account, no network dependency
beyond YouTube itself.

```
┌──────────────────────────────┐
│  Flutter app                 │
│  ──────────────────────────  │
│  youtube_explode_dart        │  search + audio manifest
│  plain HttpClient            │  byte downloads (the library's
│                              │  downloader stalls on googlevideo)
│  just_audio + audio_service  │  playback, background, car
│  sqflite                     │  library, plays, skips
│  device cache (m4a)          │  offline playback
└──────────────────────────────┘
        │
        ├──► Android Auto   (MediaBrowserServiceCompat)
        └──► CarPlay        (CPTemplateApplicationSceneDelegate)
```

Deliberate choices:

- **itag 140 (AAC/m4a, 128 kbps)** is preferred over the higher-bitrate Opus
  streams because iOS cannot play Opus-in-WebM. No transcoding is needed.
- **Downloads bypass the extractor library.** Its stream client hangs on
  googlevideo's 302 redirect; a plain `HttpClient` follows it in ~200 ms and
  gets `audio/mp4` with Range support. Files are length-checked before commit.
- **URLs expire after ~5–6 hours**, so the handler re-resolves and resumes if
  playback dies mid-session.

`server/` still exists as an optional debugging tool (yt-dlp based). If
on-device extraction breaks, comparing the two tells you whether YouTube or the
app changed.

## 3. Data model (SQLite via drift)

```sql
track(id TEXT PK, title, artist, album, duration, thumbnail,
      audio_path, bytes, cached_at, last_played, play_count, favorite)

playlist(id PK, name, created_at, updated_at)
playlist_track(playlist_id, track_id, position)

recent(track_id PK, played_at)
setting(key PK, value)
```

Every row can exist **without** a cached file (streamed-only). `audio_path`
null means "needs network".

## 4. Offline strategy

- Queue is saved to SQLite on every change; a cold start restores it.
- "Download for offline" writes `.m4a` into the app's private directory and
  fills `audio_path`.
- Auto-cache: the next 3 queue items get prefetched via `POST /prefetch` +
  a device download, so skipping in the car doesn't stall.
- iOS: mark downloaded files with `NSURLIsExcludedFromBackupKey` so they aren't
  pushed to iCloud and don't inflate the user's backup.
- Eviction: LRU, driven by `bytes`/`cached_at`, with a user-set budget in
  Settings (default 4 GB). Never evict favorited tracks.

## 5. Android Auto

Requirements, all reachable without store review:

- `audio_service` already exposes a `MediaBrowserServiceCompat` — that's the
  contract Android Auto talks to. Register it in `AndroidManifest.xml` with the
  `android.media.browse.MediaBrowserService` intent filter.
- `androidx.car.app` descriptor at
  `android/app/src/main/res/xml/automotive_app_desc.xml`:
  ```xml
  <automotiveApp>
      <uses name="media"/>
  </automotiveApp>
  ```
  referenced from the manifest as
  `com.google.android.gms.car.application` metadata.
- Build the browsable tree (Library → Playlists / Cached / Recent) with
  `MediaItem` `children` in `audio_service`.
- Testing without a car: install the **Desktop Head Unit** (in the Android SDK),
  enable Developer Mode in the Android Auto app, then `adb forward tcp:5277
  tcp:5277` and run `desktop-head-unit`.
- Sideloading to a real head unit: Android Auto app → tap version 10× →
  Developer settings → *Unknown sources*. No Play Store needed for personal use.

## 6. CarPlay

- CarPlay UI runs in a second `UIWindowScene` with
  `CPTemplateApplicationSceneDelegate`, driving `CPListTemplate`s (Library,
  Playlists, Cached). That part is Swift, ~150–250 lines in `ios/Runner/`.
- Now-playing info and remote commands can come from `audio_service`; the
  browsable templates cannot, so we add a small method channel between Dart and
  Swift.
- **Testing:** Xcode's iOS Simulator → *Features ▸ External Displays ▸ CarPlay*
  runs the templates without Apple's entitlement. For a physical car you request
  `com.apple.developer.carplay-audio` in the developer portal; for personal use
  the simulator plus a free provisioning profile is usually enough to iterate.
- iOS sideload reality: with a free Apple ID, builds expire after 7 days. With a
  paid developer account, self-signed builds last a year. Budget for that.

## 7. Status

Shipped (see GitHub releases):

| Version | Content |
| --- | --- |
| v0.1.x | first installable builds; playback fixed to the progressive MP4 stream |
| v0.2.x | home feed from listening history, YT Music-style layout, mediaItem fix, long-listen caching |
| v0.3.x | shuffle/repeat, download button, playlists, Spotify + YouTube + text import, liked/offline/downloads shelves |
| v0.4.x | Android Auto browse tree; vendor fix for "Streamed" search crash |
| v0.5.x | queue editing, synced lyrics (lrclib), sleep timer, playback speed, autoplay |
| v0.6.x | radio, personal mix, mood chips, Deezer charts, resume position, recent searches, real download %, download-all, sorting, swipe-to-skip |

Deliberately excluded, with reasons:

- **Lossless / HiFi** — YouTube serves no lossless audio.
- **Hum-to-search** — requires an audio fingerprint service.
- **AI DJ voice** — requires a backend and TTS.
- **Casting** — requires the Cast SDK and a receiver.
- **Accounts / sync** — needs OAuth credentials and a provider.
- **CarPlay** — Apple gates it behind a manually granted entitlement.
- **Equalizer on iOS** — `just_audio` has no iOS equalizer; Android only.

## 8. Phases

**Phase 1 — resolver (done)**
- [x] `/search`, `/resolve`, `/audio` with Range support
- [x] disk cache with LRU eviction, metadata sidecars
- [x] API key, prefetch endpoint
- [ ] cookies flag for "confirm you're not a bot" (only if it bites)

**Phase 2 — Flutter shell (playback + search + cache)**
- [x] `flutter create --org dev.aurora --platforms android,ios mobile`
- [x] `just_audio` + `audio_service`, background playback, lock screen
- [x] Resolver client (`lib/data/resolver_api.dart`) with retry + key header
- [x] Search screen, play, cache-to-device, offline tab
- [x] Automatic caching after N qualified plays (see below)
- [ ] verify on a physical phone with Wi-Fi off

**Phase 2.5 — automatic caching (implemented)**
- Qualified play = 30 s or half the track, whichever is shorter.
- Early skip = switched away before that; subtracts from affinity.
- `affinity = plays − skips`; at threshold, download to device in background.
- Favourites cache regardless; >20 min uploads require a manual save.
- Budget-driven LRU eviction that never touches manual saves or favourites.
- Unit-tested in `mobile/test/auto_cache_policy_test.dart`.

**Phase 3 — library, playlists, offline UX**
- drift schema above, import from the resolver's `/cache`
- Playlists, favorites, recent, downloads manager with size budget
- Prefetch of next 3 queue items

**Phase 4 — Android Auto**
- Manifest service + `automotive_app_desc.xml`
- Browse tree: Playlists / Cached / Recent
- DHU pass, then real car

**Phase 5 — CarPlay**
- Swift scene delegate + `CPListTemplate` browsing
- Method channel to Dart for "play this track id"
- Simulator pass, then paid-account device install

**Phase 6 — polish**
- Equalizer (port the 10-band graph logic from `src/lib/audio/engine.ts`)
- Sleep timer, playback speed, lyrics, themes

## 8. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| yt-dlp breaks after a YouTube change | playback fails, whole app | upgrade yt-dlp; keep resolver on the Mac where it's one command |
| YouTube bot-check on the resolver IP | downloads fail | `--cookies-from-browser`, or run resolver over Tailscale |
| iOS 7-day provisioning (free account) | app stops launching weekly | paid developer account, or accept re-signing |
| CarPlay entitlement denial | no physical-car CarPlay | simulator still works; personal use rarely needs it |
| Opus/WebM on iOS | silent playback | server always normalises to m4a |
| Phone can't reach the Mac away from home | no streaming | Tailscale, not port-forwarding |

## 9. Non-goals

- Publishing to either store.
- Multi-user accounts or sync.
- Anything resembling a service others rely on.
