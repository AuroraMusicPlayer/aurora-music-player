# Aurora Music

Aurora Music is a private, standalone music player for web, Android, and iOS. It is a React/Vite application packaged with Capacitor; it has no Lovable runtime, hosting, or build dependency.

## What works

- Import local MP3, FLAC, AAC, M4A, OGG, WAV, ALAC, and Opus files.
- Read metadata, embedded artwork, and lyrics.
- Play queues with shuffle, repeat, favorites, playlists, sleep timer, speed, and a 10-band equalizer.
- Search and play YouTube through a visible embedded player.
- Open a direct YouTube link without an API key.
- Search by song name and import public playlists with the YouTube Data API.
- Save online songs, history, play counts, and a personal “online rotation.”
- Keep the online player mounted while navigating inside Aurora.
- Manually download eligible direct-audio URLs for offline use.
- Smart-cache only direct audio the user has confirmed may be downloaded, with Wi-Fi/always/off modes and a storage-size limit.
- Keep local/permitted audio playing in the background with lock-screen, notification, Bluetooth, and media-button controls.
- Produce an Android debug APK and unsigned iOS simulator build in GitHub Actions.

## Provider and offline rules

Aurora deliberately separates hosted online music from its native/offline library.

| Source                     | Playback              | Offline storage       | Background/native controls  |
| -------------------------- | --------------------- | --------------------- | --------------------------- |
| Local files                | Aurora audio engine   | Always local          | Yes                         |
| Permitted direct audio URL | Aurora audio engine   | Manual or smart cache | Yes                         |
| YouTube                    | Visible YouTube embed | No                    | Provider/platform dependent |

Aurora does not extract YouTube audio, hide the provider player, remove advertising, bypass subscriptions, or download hosted streams. Private use does not change a provider's playback or copyright rules.

## YouTube setup

Direct YouTube video links work immediately. Searching by name and importing playlists uses the official YouTube Data API:

1. Open [Google Cloud Console](https://console.cloud.google.com/apis/library/youtube.googleapis.com).
2. Enable **YouTube Data API v3** in a Google Cloud project.
3. Create an API key and restrict it to that API.
4. Paste the key into **Aurora → Settings → Online music**.

The key is stored only in the app's local storage. It can alternatively be supplied at build time as `VITE_YOUTUBE_API_KEY`.

## Android, iOS, and cars

Android uses a foreground media session while local/permitted audio is active. iOS enables the playback audio session and background-audio mode. These integrations provide system Now Playing controls and normally make playback controllable from Bluetooth and compatible car head units.

Full dashboard browsing is a separate platform approval/integration layer:

- **CarPlay:** Apple must grant the CarPlay audio-app entitlement to the developer account before an app icon and browsable library can be installed on CarPlay. Standard Now Playing controls do not require Aurora to copy a CarPlay UI.
- **Android Auto:** a full browsable app needs a native `MediaLibraryService` catalog and Android Auto testing/distribution approval. The current media session provides playback controls, but not a standalone Android Auto catalog screen.
- YouTube video playback is not exposed as a car media source and cannot be converted into background audio by Aurora.

## Development

Requirements:

- Node.js 22+
- Java 21 and Android Studio for Android
- macOS with Xcode for iOS

```bash
npm ci
npm run check
npm run dev
```

Native projects:

```bash
npm run cap:sync
npm run android
npm run ios
```

`npm run check` runs TypeScript, unit tests, and the production Vite build. GitHub Actions repeats these checks, assembles a debug APK, and compiles the iOS simulator app. A device-installable iOS IPA still requires the owner's Apple Developer signing certificate and provisioning profile.

## Architecture

- `src/store/player.ts` — local/direct library, queue, playback, and offline cache.
- `src/store/online.ts` — saved YouTube items, history, playlists, and listening statistics.
- `src/lib/audio/engine.ts` — HTML audio, equalizer, and native/web media sessions.
- `src/lib/smartCache.ts` — permission-gated, size-limited direct-audio cache.
- `src/lib/youtube.ts` — strict URL parsing and official YouTube Data API client.
- `android/` and `ios/` — Capacitor native shells and background-audio configuration.

## Privacy

Imported files, cache records, listening statistics, playlists, settings, and API keys remain on the device. Aurora has no application server and uploads no personal library data.
