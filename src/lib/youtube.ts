import type { OnlineTrack } from "./types";

const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;
const PLAYLIST_ID_RE = /^[A-Za-z0-9_-]{10,80}$/;

const VALID_YOUTUBE_HOSTS = new Set([
  "youtube.com",
  "www.youtube.com",
  "music.youtube.com",
  "m.youtube.com",
  "youtu.be",
]);

export function extractYouTubeVideoId(raw: string): string | null {
  const value = raw.trim();
  if (VIDEO_ID_RE.test(value)) return value;

  try {
    const url = new URL(value);
    if (!VALID_YOUTUBE_HOSTS.has(url.hostname)) return null;
    if (url.hostname === "youtu.be") {
      const id = url.pathname.slice(1).split("/")[0];
      return VIDEO_ID_RE.test(id) ? id : null;
    }
    const queryId = url.searchParams.get("v");
    if (queryId && VIDEO_ID_RE.test(queryId)) return queryId;
    const pathMatch = url.pathname.match(/\/(?:embed|shorts|live)\/([A-Za-z0-9_-]{11})(?:\/|$)/);
    return pathMatch?.[1] ?? null;
  } catch {
    return null;
  }
}

export function extractYouTubePlaylistId(raw: string): string | null {
  try {
    const url = new URL(raw.trim());
    if (!VALID_YOUTUBE_HOSTS.has(url.hostname)) return null;
    const id = url.searchParams.get("list");
    return id && PLAYLIST_ID_RE.test(id) ? id : null;
  } catch {
    return null;
  }
}

export function youtubeWatchUrl(videoId: string): string {
  if (!VIDEO_ID_RE.test(videoId)) throw new Error("Invalid YouTube video ID");
  return `https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`;
}

export function youtubeMusicUrl(videoId: string): string {
  if (!VIDEO_ID_RE.test(videoId)) throw new Error("Invalid YouTube video ID");
  return `https://music.youtube.com/watch?v=${encodeURIComponent(videoId)}`;
}

export function youtubeThumbnail(videoId: string): string {
  if (!VIDEO_ID_RE.test(videoId)) return "";
  return `https://i.ytimg.com/vi/${encodeURIComponent(videoId)}/mqdefault.jpg`;
}

interface YouTubeSearchItem {
  id?: { videoId?: string };
  snippet?: {
    title?: string;
    channelTitle?: string;
    thumbnails?: {
      medium?: { url?: string };
      high?: { url?: string };
      default?: { url?: string };
    };
  };
}

interface YouTubePlaylistItem {
  snippet?: {
    title?: string;
    videoOwnerChannelTitle?: string;
    channelTitle?: string;
    resourceId?: { videoId?: string };
    thumbnails?: YouTubeSearchItem["snippet"] extends infer T
      ? T extends { thumbnails?: infer P }
        ? P
        : never
      : never;
  };
}

interface YouTubeListResponse<T> {
  items?: T[];
  nextPageToken?: string;
  error?: { message?: string };
}

export interface YouTubePage {
  tracks: OnlineTrack[];
  nextPageToken: string | null;
}

function decodeHtml(value: string): string {
  const element = document.createElement("textarea");
  element.innerHTML = value;
  return element.value;
}

function toTrack(item: YouTubeSearchItem, now = Date.now()): OnlineTrack | null {
  const videoId = item.id?.videoId;
  if (!videoId || !VIDEO_ID_RE.test(videoId)) return null;
  const snippet = item.snippet;
  return {
    id: `youtube:${videoId}`,
    videoId,
    title: decodeHtml(snippet?.title || "Untitled"),
    artist: decodeHtml(snippet?.channelTitle || "YouTube"),
    artwork:
      snippet?.thumbnails?.high?.url ||
      snippet?.thumbnails?.medium?.url ||
      snippet?.thumbnails?.default?.url ||
      youtubeThumbnail(videoId),
    provider: "youtube",
    addedAt: now,
  };
}

function assertApiKey(apiKey: string) {
  if (!apiKey.trim()) {
    throw new Error("Add your free YouTube Data API key in Aurora Settings first.");
  }
}

async function getJson<T>(url: URL): Promise<T> {
  const response = await fetch(url, { credentials: "omit" });
  const body = (await response.json()) as T & { error?: { message?: string } };
  if (!response.ok) {
    throw new Error(body.error?.message || `YouTube request failed (${response.status})`);
  }
  return body;
}

export async function searchYouTube(
  query: string,
  apiKey: string,
  pageToken?: string,
): Promise<YouTubePage> {
  assertApiKey(apiKey);
  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  url.searchParams.set("part", "snippet");
  url.searchParams.set("type", "video");
  url.searchParams.set("videoCategoryId", "10");
  url.searchParams.set("videoEmbeddable", "true");
  url.searchParams.set("videoSyndicated", "true");
  url.searchParams.set("maxResults", "25");
  url.searchParams.set("q", query.trim());
  url.searchParams.set("key", apiKey.trim());
  if (pageToken) url.searchParams.set("pageToken", pageToken);

  const data = await getJson<YouTubeListResponse<YouTubeSearchItem>>(url);
  return {
    tracks: (data.items ?? []).map((item) => toTrack(item)).filter(Boolean) as OnlineTrack[],
    nextPageToken: data.nextPageToken ?? null,
  };
}

export async function importYouTubePlaylist(
  playlistId: string,
  apiKey: string,
  maxTracks = 200,
): Promise<OnlineTrack[]> {
  assertApiKey(apiKey);
  if (!PLAYLIST_ID_RE.test(playlistId)) throw new Error("Invalid YouTube playlist");

  const tracks: OnlineTrack[] = [];
  let pageToken: string | undefined;

  do {
    const url = new URL("https://www.googleapis.com/youtube/v3/playlistItems");
    url.searchParams.set("part", "snippet");
    url.searchParams.set("playlistId", playlistId);
    url.searchParams.set("maxResults", "50");
    url.searchParams.set("key", apiKey.trim());
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const data = await getJson<YouTubeListResponse<YouTubePlaylistItem>>(url);
    for (const item of data.items ?? []) {
      const videoId = item.snippet?.resourceId?.videoId;
      if (!videoId || !VIDEO_ID_RE.test(videoId)) continue;
      tracks.push({
        id: `youtube:${videoId}`,
        videoId,
        title: decodeHtml(item.snippet?.title || "Untitled"),
        artist: decodeHtml(
          item.snippet?.videoOwnerChannelTitle || item.snippet?.channelTitle || "YouTube",
        ),
        artwork:
          item.snippet?.thumbnails?.high?.url ||
          item.snippet?.thumbnails?.medium?.url ||
          item.snippet?.thumbnails?.default?.url ||
          youtubeThumbnail(videoId),
        provider: "youtube",
        addedAt: Date.now(),
      });
      if (tracks.length >= maxTracks) return tracks;
    }
    pageToken = data.nextPageToken;
  } while (pageToken);

  return tracks;
}
