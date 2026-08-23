// YouTube player component for Aurora Music.
// Lets users paste a YouTube or YouTube Music URL and play it via the
// official YouTube IFrame embed — no unofficial APIs, fully within YouTube ToS.

import { useEffect, useRef, useState } from "react";
import { Play, ExternalLink, Clock, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";

const YT_HISTORY_KEY = "aurora-yt-history";
const MAX_HISTORY = 12;

interface YtEntry {
  videoId: string;
  /** The original URL the user pasted. */
  url: string;
  addedAt: number;
}

const VALID_YOUTUBE_HOSTS = new Set([
  "youtube.com",
  "www.youtube.com",
  "music.youtube.com",
  "m.youtube.com",
]);

/** Extract a YouTube video ID from common URL patterns. */
function extractVideoId(raw: string): string | null {
  const trimmed = raw.trim();
  // Bare video ID — 11 alphanumeric chars
  if (/^[A-Za-z0-9_-]{11}$/.test(trimmed)) return trimmed;
  try {
    const u = new URL(trimmed);
    if (VALID_YOUTUBE_HOSTS.has(u.hostname)) {
      const v = u.searchParams.get("v");
      if (v && /^[A-Za-z0-9_-]{11}$/.test(v)) return v;
      // /embed/<id>
      const m = u.pathname.match(/\/embed\/([A-Za-z0-9_-]{11})/);
      if (m) return m[1];
      // /shorts/<id>
      const s = u.pathname.match(/\/shorts\/([A-Za-z0-9_-]{11})/);
      if (s) return s[1];
    }
    // youtu.be/<id>
    if (u.hostname === "youtu.be") {
      const id = u.pathname.slice(1).split("?")[0];
      if (/^[A-Za-z0-9_-]{11}$/.test(id)) return id;
    }
  } catch {
    /* not a valid URL — fall through */
  }
  return null;
}

function loadHistory(): YtEntry[] {
  if (typeof localStorage === "undefined") return [];
  try {
    const raw = JSON.parse(localStorage.getItem(YT_HISTORY_KEY) || "[]") as unknown[];
    // Validate each entry to guard against tampered localStorage.
    return raw.filter((e): e is YtEntry => {
      if (typeof e !== "object" || e === null) return false;
      const entry = e as Record<string, unknown>;
      return (
        typeof entry.videoId === "string" &&
        /^[A-Za-z0-9_-]{11}$/.test(entry.videoId) &&
        typeof entry.url === "string" &&
        typeof entry.addedAt === "number"
      );
    });
  } catch {
    return [];
  }
}

function saveHistory(entries: YtEntry[]) {
  if (typeof localStorage === "undefined") return;
  localStorage.setItem(YT_HISTORY_KEY, JSON.stringify(entries));
}

export function YouTubePlayer() {
  const [url, setUrl] = useState("");
  const [videoId, setVideoId] = useState<string | null>(null);
  const [history, setHistory] = useState<YtEntry[]>(loadHistory);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  function handlePlay(rawUrl?: string) {
    const input = rawUrl ?? url;
    const id = extractVideoId(input);
    if (!id) {
      toast.error("Paste a valid YouTube or YouTube Music URL");
      return;
    }
    setVideoId(id);
    const entry: YtEntry = { videoId: id, url: input.trim(), addedAt: Date.now() };
    const next = [entry, ...history.filter((h) => h.videoId !== id)].slice(
      0,
      MAX_HISTORY,
    );
    setHistory(next);
    saveHistory(next);
  }

  function clearHistory() {
    setHistory([]);
    saveHistory([]);
  }

  return (
    <div className="space-y-5 pb-6">
      {/* Input */}
      <div className="px-4 flex gap-2">
        <Input
          ref={inputRef}
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handlePlay()}
          placeholder="Paste YouTube or YouTube Music URL…"
          className="rounded-xl"
        />
        <Button
          onClick={() => handlePlay()}
          disabled={!url.trim()}
          className="rounded-xl shrink-0"
        >
          <Play className="h-4 w-4 mr-1" fill="currentColor" />
          Play
        </Button>
      </div>

      {/* Embedded player */}
      {videoId && (
        <div className="px-4">
          <div className="relative aspect-video w-full overflow-hidden rounded-2xl shadow-lg">
            <iframe
              key={videoId}
              src={`https://www.youtube.com/embed/${videoId}?autoplay=1&rel=0&modestbranding=1`}
              title="YouTube player"
              allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
              allowFullScreen
              className="absolute inset-0 h-full w-full border-0"
            />
          </div>
          <div className="mt-2 flex justify-end gap-2">
            <a
              href={`https://music.youtube.com/watch?v=${videoId}`}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1 text-xs text-muted-foreground hover:text-primary transition-colors"
            >
              <ExternalLink className="h-3.5 w-3.5" />
              Open in YouTube Music
            </a>
          </div>
        </div>
      )}

      {/* Info note */}
      {!videoId && (
        <p className="px-4 text-xs text-muted-foreground">
          Paste any YouTube or YouTube Music link. The video plays in the embedded
          YouTube player — no account needed. Aurora cannot cache YouTube audio
          (YouTube's Terms of Service do not allow it), but local tracks you import
          are automatically cached for offline use.
        </p>
      )}

      {/* History */}
      {history.length > 0 && (
        <section className="px-2">
          <div className="flex items-center justify-between px-2 mb-2">
            <h2 className="text-base font-bold font-display flex items-center gap-1.5">
              <Clock className="h-4 w-4" /> Recently played
            </h2>
            <button
              onClick={clearHistory}
              className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
            >
              <X className="h-3.5 w-3.5" /> Clear
            </button>
          </div>
          <div className="space-y-0.5">
            {history.map((entry) => (
              <button
                key={entry.videoId}
                onClick={() => {
                  setUrl(entry.url);
                  handlePlay(entry.url);
                }}
                className="group flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left transition-colors hover:bg-accent/60"
              >
                <div className="relative h-14 w-24 shrink-0 overflow-hidden rounded-lg bg-muted">
                  <img
                    src={`https://img.youtube.com/vi/${encodeURIComponent(entry.videoId)}/mqdefault.jpg`}
                    alt=""
                    className="h-full w-full object-cover"
                    loading="lazy"
                  />
                  <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity bg-black/40 rounded-lg">
                    <Play className="h-5 w-5 text-white" fill="currentColor" />
                  </div>
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">
                    youtube.com/watch?v={entry.videoId}
                  </p>
                  <p className="text-xs text-muted-foreground">YouTube</p>
                </div>
                <a
                  href={`https://music.youtube.com/watch?v=${encodeURIComponent(entry.videoId)}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={(e) => e.stopPropagation()}
                  className="shrink-0 p-1.5 text-muted-foreground hover:text-primary"
                  title="Open in YouTube Music"
                >
                  <ExternalLink className="h-4 w-4" />
                </a>
              </button>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
