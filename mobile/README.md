# Aurora Music — mobile app

Flutter client that plays YouTube audio, keeps it offline, and works entirely on
the device — **no computer or server needed**.

## What it does today

- Search YouTube from the phone and play immediately.
- Background playback, lock screen and notification controls (`audio_service`).
- **Automatic offline caching**: after 2 qualified plays a track is saved to the
  device and plays with no network at all.
- Manual save (long-press a result), manual remove, cache budget with LRU
  eviction.
- Android Auto is declared in the manifest; browsable car UI and CarPlay come
  next.

## Run it

```sh
cd mobile
flutter run
```

Nothing to configure: no URL, no API key, no server.

## How automatic caching works

A play only counts once playback passes **30 seconds, or half the track** if
it's shorter. Switching away before that counts as a **skip**.

```
affinity = plays − early skips
```

When `affinity` reaches the threshold (default 2, configurable 1–10 in Settings)
the track is downloaded in the background to the app's private storage and
enters the Offline tab.

| Behaviour | Why |
| --- | --- |
| Skips subtract | A song you keep rejecting never fills your storage just because it appeared in a queue. |
| Favourites cache even with auto-cache off | Favouriting is explicit intent. |
| Uploads over 20 minutes need a manual save | Otherwise one DJ set eats the whole budget. |
| Wi-Fi only by default | Auto-downloads shouldn't spend mobile data. |
| Eviction is LRU, auto-cached only | Manual saves and favourites are never deleted behind your back. |
| iOS files excluded from iCloud backup | Otherwise downloads inflate the user's backup. |

Checked in `test/auto_cache_policy_test.dart` — run `flutter test`.

## How the audio is obtained

`youtube_explode_dart` resolves search results and the audio manifest; the app
prefers itag 140 (AAC/m4a, 128 kbps) because iOS cannot play Opus-in-WebM.

Byte downloads deliberately **do not** use the library's downloader — it stalls
on googlevideo's 302 redirect. `DeviceCache` follows the redirect with a plain
`HttpClient` and verifies the resulting size before committing the file.

Signed stream URLs expire after roughly 5–6 hours; the handler re-resolves and
resumes if playback dies mid-session.

## Android Auto

Wired: `automotive_app_desc.xml`, the `AudioService` manifest entry, and
`MainActivity : AudioServiceActivity()`.

Test without a car:

```sh
adb forward tcp:5277 tcp:5277
$ANDROID_HOME/extras/google/auto/desktop-head-unit
```

Real head unit: Android Auto app → tap *Version* 10× → Developer settings →
enable *Unknown sources*.

## Roadmap

See `../docs/PLAN.md`. Next: browsable Android Auto tree, CarPlay templates,
playlists, equalizer.

## `../server/`

Optional and no longer used by the app. It remains as a debugging tool: if
on-device extraction ever breaks, the yt-dlp based resolver shows whether the
problem is YouTube or the app.
