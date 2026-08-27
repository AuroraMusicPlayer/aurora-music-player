import { describe, expect, it } from "vitest";

import {
  extractYouTubePlaylistId,
  extractYouTubeVideoId,
  youtubeMusicUrl,
  youtubeThumbnail,
  youtubeWatchUrl,
} from "./youtube";

const VIDEO_ID = "dQw4w9WgXcQ";

describe("YouTube URL parsing", () => {
  it.each([
    [VIDEO_ID, VIDEO_ID],
    [`https://www.youtube.com/watch?v=${VIDEO_ID}`, VIDEO_ID],
    [`https://music.youtube.com/watch?v=${VIDEO_ID}&list=PL1234567890`, VIDEO_ID],
    [`https://youtu.be/${VIDEO_ID}?si=abc`, VIDEO_ID],
    [`https://www.youtube.com/shorts/${VIDEO_ID}`, VIDEO_ID],
    [`https://www.youtube.com/embed/${VIDEO_ID}`, VIDEO_ID],
  ])("extracts a valid video ID from %s", (input, expected) => {
    expect(extractYouTubeVideoId(input)).toBe(expected);
  });

  it.each([
    "https://example.com/watch?v=dQw4w9WgXcQ",
    "https://youtube.com/watch?v=too-short",
    "javascript:alert(1)",
    "not a URL",
  ])("rejects unsafe or invalid video input: %s", (input) => {
    expect(extractYouTubeVideoId(input)).toBeNull();
  });

  it("extracts a playlist only from an approved YouTube host", () => {
    expect(extractYouTubePlaylistId("https://www.youtube.com/playlist?list=PL1234567890")).toBe(
      "PL1234567890",
    );
    expect(extractYouTubePlaylistId("https://example.com/?list=PL1234567890")).toBeNull();
  });
});

describe("YouTube URL builders", () => {
  it("builds canonical provider URLs", () => {
    expect(youtubeWatchUrl(VIDEO_ID)).toBe(`https://www.youtube.com/watch?v=${VIDEO_ID}`);
    expect(youtubeMusicUrl(VIDEO_ID)).toBe(`https://music.youtube.com/watch?v=${VIDEO_ID}`);
    expect(youtubeThumbnail(VIDEO_ID)).toContain(`/vi/${VIDEO_ID}/`);
  });

  it("rejects invalid IDs", () => {
    expect(() => youtubeWatchUrl("bad")).toThrow("Invalid YouTube video ID");
    expect(youtubeThumbnail("bad")).toBe("");
  });
});
