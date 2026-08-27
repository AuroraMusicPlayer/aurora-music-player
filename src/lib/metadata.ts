// Audio metadata extraction using music-metadata (browser build).
// Extracts tags, embedded artwork and embedded lyrics from local files.

import { parseBlob } from "music-metadata";
import type { Track } from "./types";

export const SUPPORTED_EXTENSIONS = ["mp3", "flac", "aac", "m4a", "ogg", "wav", "alac", "opus"];

export function isSupportedAudio(file: File): boolean {
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
  if (SUPPORTED_EXTENSIONS.includes(ext)) return true;
  return file.type.startsWith("audio/");
}

function uid(): string {
  return `t_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 9)}`;
}

function deriveFolder(file: File): string {
  // webkitRelativePath is set for directory picks. Otherwise group under "Imported".
  const rel = (file as File & { webkitRelativePath?: string }).webkitRelativePath;
  if (rel && rel.includes("/")) {
    const parts = rel.split("/");
    parts.pop(); // drop filename
    return parts.join("/") || "Imported";
  }
  return "Imported";
}

/** Parse a local audio File into a Track plus its artwork blob (if any). */
export async function parseTrack(file: File): Promise<{ track: Track; artBlob: Blob | null }> {
  const id = uid();
  const base: Track = {
    id,
    title: file.name.replace(/\.[^.]+$/, ""),
    artist: "Unknown Artist",
    album: "Unknown Album",
    albumArtist: "Unknown Artist",
    genre: "Unknown",
    year: null,
    duration: 0,
    trackNo: null,
    folder: deriveFolder(file),
    source: "local",
    url: "",
    artwork: null,
    lyrics: null,
    addedAt: Date.now(),
    fileName: file.name,
  };

  let artBlob: Blob | null = null;

  try {
    const meta = await parseBlob(file, { duration: true });
    const c = meta.common;
    base.title = c.title?.trim() || base.title;
    base.artist = c.artist?.trim() || base.artist;
    base.album = c.album?.trim() || base.album;
    base.albumArtist = c.albumartist?.trim() || base.artist;
    base.genre = c.genre?.[0]?.trim() || base.genre;
    base.year = c.year ?? null;
    base.trackNo = c.track?.no ?? null;
    base.duration = meta.format.duration ? Math.round(meta.format.duration) : 0;

    const lyricEntry = c.lyrics?.[0];
    if (lyricEntry) {
      base.lyrics =
        typeof lyricEntry === "string"
          ? lyricEntry
          : (lyricEntry.text ?? lyricEntry.syncText?.map((s) => s.text).join("\n") ?? null);
    }

    if (c.picture && c.picture.length > 0) {
      const pic = c.picture[0];
      artBlob = new Blob([pic.data as unknown as BlobPart], { type: pic.format });
      base.artwork = URL.createObjectURL(artBlob);
    }
  } catch {
    // Unreadable tags — keep filename-based defaults.
  }

  return { track: base, artBlob };
}

/** Build a Track from a direct, streamable audio URL. */
export function trackFromUrl(url: string, title?: string, downloadAllowed = false): Track {
  const cleanName = (() => {
    try {
      const u = new URL(url);
      return decodeURIComponent(u.pathname.split("/").pop() || "Stream");
    } catch {
      return "Stream";
    }
  })();
  return {
    id: uid(),
    title: title?.trim() || cleanName.replace(/\.[^.]+$/, ""),
    artist: "Web Stream",
    album: "Streamed",
    albumArtist: "Web Stream",
    genre: "Stream",
    year: null,
    duration: 0,
    trackNo: null,
    folder: "Streams",
    source: "url",
    url,
    downloadAllowed,
    artwork: null,
    lyrics: null,
    addedAt: Date.now(),
    fileName: cleanName,
  };
}
