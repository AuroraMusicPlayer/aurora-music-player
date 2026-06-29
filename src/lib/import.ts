// Import pipeline: turn picked Files into Tracks, persisting audio + artwork
// blobs to IndexedDB. Returns the parsed tracks (with runtime artwork URLs).

import { parseTrack, isSupportedAudio } from "./metadata";
import { putBlob } from "./db";
import type { Track } from "./types";

export interface ImportProgress {
  done: number;
  total: number;
}

export async function importFiles(
  files: File[],
  onProgress?: (p: ImportProgress) => void,
): Promise<Track[]> {
  const audioFiles = files.filter(isSupportedAudio);
  const tracks: Track[] = [];
  let done = 0;
  for (const file of audioFiles) {
    try {
      const { track, artBlob } = await parseTrack(file);
      await putBlob(track.id, file);
      if (artBlob) await putBlob(`art_${track.id}`, artBlob);
      tracks.push(track);
    } catch {
      /* skip unreadable file */
    }
    done += 1;
    onProgress?.({ done, total: audioFiles.length });
  }
  return tracks;
}
