import { useMemo, useState } from "react";
import { Link } from "@tanstack/react-router";
import {
  Bookmark,
  Check,
  Clock,
  ExternalLink,
  KeyRound,
  ListPlus,
  LoaderCircle,
  Play,
  Search,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  extractYouTubePlaylistId,
  extractYouTubeVideoId,
  importYouTubePlaylist,
  searchYouTube,
  youtubeThumbnail,
  youtubeWatchUrl,
  type YouTubePage,
} from "@/lib/youtube";
import type { OnlineTrack } from "@/lib/types";
import { useOnline } from "@/store/online";
import { useSettings } from "@/store/settings";
import { usePlayer } from "@/store/player";

export function YouTubePlayer() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<OnlineTrack[]>([]);
  const [nextPageToken, setNextPageToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [importing, setImporting] = useState(false);

  const configuredKey = useSettings((state) => state.youtubeApiKey);
  const apiKey = configuredKey || import.meta.env.VITE_YOUTUBE_API_KEY || "";
  const current = useOnline((state) => state.current);
  const history = useOnline((state) => state.history);
  const saved = useOnline((state) => state.saved);
  const playOnline = useOnline((state) => state.play);
  const saveTrack = useOnline((state) => state.saveTrack);
  const removeSaved = useOnline((state) => state.removeSaved);
  const importPlaylist = useOnline((state) => state.importPlaylist);
  const clearHistory = useOnline((state) => state.clearHistory);

  const savedIds = useMemo(() => new Set(saved.map((track) => track.videoId)), [saved]);
  const playlistId = extractYouTubePlaylistId(query);

  function trackFromVideoId(videoId: string): OnlineTrack {
    const known = [...results, ...history, ...saved, ...(current ? [current] : [])].find(
      (track) => track.videoId === videoId,
    );
    return (
      known ?? {
        id: `youtube:${videoId}`,
        videoId,
        title: "YouTube video",
        artist: "YouTube",
        artwork: youtubeThumbnail(videoId),
        provider: "youtube",
        addedAt: Date.now(),
      }
    );
  }

  function play(track: OnlineTrack) {
    usePlayer.getState().dismiss();
    playOnline(track);
  }

  async function submit(loadMore = false) {
    const value = query.trim();
    if (!value) return;

    const videoId = extractYouTubeVideoId(value);
    if (videoId && !loadMore) {
      play(trackFromVideoId(videoId));
      return;
    }

    if (!apiKey) {
      toast.error("Add your free YouTube API key in Settings to search by name.");
      return;
    }

    setLoading(true);
    try {
      const page: YouTubePage = await searchYouTube(
        value,
        apiKey,
        loadMore ? (nextPageToken ?? undefined) : undefined,
      );
      setResults((previous) => (loadMore ? [...previous, ...page.tracks] : page.tracks));
      setNextPageToken(page.nextPageToken);
      if (!loadMore && page.tracks.length === 0) toast.info("No videos found");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "YouTube search failed");
    } finally {
      setLoading(false);
    }
  }

  async function handleImport() {
    if (!playlistId) {
      toast.error("Paste a valid YouTube playlist URL");
      return;
    }
    if (!apiKey) {
      toast.error("Add your free YouTube API key in Settings first.");
      return;
    }
    setImporting(true);
    try {
      const tracks = await importYouTubePlaylist(playlistId, apiKey);
      if (tracks.length === 0) {
        toast.error("This playlist is empty or private");
        return;
      }
      const name = `YouTube playlist · ${new Date().toLocaleDateString()}`;
      importPlaylist(name, tracks);
      setResults(tracks);
      toast.success(`Imported ${tracks.length} songs`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Playlist import failed");
    } finally {
      setImporting(false);
    }
  }

  function toggleSaved(track: OnlineTrack) {
    if (savedIds.has(track.videoId)) {
      removeSaved(track.videoId);
      toast.success("Removed from online library");
    } else {
      saveTrack(track);
      toast.success("Saved to online library");
    }
  }

  return (
    <div className="space-y-5 pb-6">
      <div className="space-y-2 px-4 pt-2">
        <div className="glass flex items-center gap-2 rounded-2xl px-3 py-2">
          <Search className="h-5 w-5 shrink-0 text-muted-foreground" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={(event) => event.key === "Enter" && void submit(false)}
            placeholder="Song, artist, YouTube link or playlist…"
            className="h-10 flex-1 border-0 bg-transparent px-1 shadow-none focus-visible:ring-0"
          />
          {query && (
            <button
              type="button"
              aria-label="Clear search"
              onClick={() => {
                setQuery("");
                setResults([]);
                setNextPageToken(null);
              }}
              className="p-1 text-muted-foreground"
            >
              <X className="h-4 w-4" />
            </button>
          )}
          <Button
            size="sm"
            className="rounded-xl"
            disabled={loading || !query.trim()}
            onClick={() => void submit(false)}
          >
            {loading ? <LoaderCircle className="h-4 w-4 animate-spin" /> : "Search"}
          </Button>
        </div>

        {playlistId && (
          <Button
            variant="secondary"
            className="w-full rounded-xl"
            disabled={importing}
            onClick={() => void handleImport()}
          >
            {importing ? (
              <LoaderCircle className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <ListPlus className="mr-2 h-4 w-4" />
            )}
            Import this YouTube playlist
          </Button>
        )}

        {!apiKey && (
          <div className="rounded-xl border border-primary/25 bg-primary/5 p-3 text-xs text-muted-foreground">
            <p className="flex items-center gap-1.5 font-medium text-foreground">
              <KeyRound className="h-4 w-4 text-primary" />
              Search setup
            </p>
            <p className="mt-1">
              Direct YouTube links already work. Add a free YouTube Data API key to search songs by
              name and import playlists.
            </p>
            <Link to="/settings" className="mt-2 inline-flex font-semibold text-primary">
              Open Settings
            </Link>
          </div>
        )}
      </div>

      {results.length > 0 && (
        <TrackSection
          title="Search results"
          tracks={results}
          savedIds={savedIds}
          onPlay={play}
          onToggleSaved={toggleSaved}
        />
      )}

      {nextPageToken && (
        <div className="px-4">
          <Button
            variant="secondary"
            className="w-full rounded-xl"
            disabled={loading}
            onClick={() => void submit(true)}
          >
            {loading && <LoaderCircle className="mr-2 h-4 w-4 animate-spin" />}
            Load more
          </Button>
        </div>
      )}

      {saved.length > 0 && results.length === 0 && (
        <TrackSection
          title="Saved online"
          tracks={saved.slice(0, 30)}
          savedIds={savedIds}
          onPlay={play}
          onToggleSaved={toggleSaved}
        />
      )}

      {history.length > 0 && (
        <section className="px-2">
          <div className="mb-2 flex items-center justify-between px-2">
            <h2 className="flex items-center gap-1.5 text-base font-bold font-display">
              <Clock className="h-4 w-4" />
              Recently played
            </h2>
            <button type="button" onClick={clearHistory} className="text-xs text-muted-foreground">
              Clear
            </button>
          </div>
          <div className="space-y-0.5">
            {history.slice(0, 12).map((track) => (
              <OnlineTrackRow
                key={track.videoId}
                track={track}
                saved={savedIds.has(track.videoId)}
                onPlay={play}
                onToggleSaved={toggleSaved}
              />
            ))}
          </div>
        </section>
      )}

      {!current && results.length === 0 && history.length === 0 && (
        <p className="px-4 text-xs leading-relaxed text-muted-foreground">
          Aurora plays online videos through YouTube's visible player, like a smart music browser.
          Online audio is not downloaded. Your imported audio files remain available in Aurora's
          separate offline library.
        </p>
      )}
    </div>
  );
}

function TrackSection({
  title,
  tracks,
  savedIds,
  onPlay,
  onToggleSaved,
}: {
  title: string;
  tracks: OnlineTrack[];
  savedIds: Set<string>;
  onPlay: (track: OnlineTrack) => void;
  onToggleSaved: (track: OnlineTrack) => void;
}) {
  return (
    <section className="px-2">
      <h2 className="mb-2 px-2 text-base font-bold font-display">{title}</h2>
      <div className="space-y-0.5">
        {tracks.map((track) => (
          <OnlineTrackRow
            key={track.videoId}
            track={track}
            saved={savedIds.has(track.videoId)}
            onPlay={onPlay}
            onToggleSaved={onToggleSaved}
          />
        ))}
      </div>
    </section>
  );
}

function OnlineTrackRow({
  track,
  saved,
  onPlay,
  onToggleSaved,
}: {
  track: OnlineTrack;
  saved: boolean;
  onPlay: (track: OnlineTrack) => void;
  onToggleSaved: (track: OnlineTrack) => void;
}) {
  return (
    <div className="group flex items-center gap-3 rounded-xl px-2 py-2 hover:bg-accent/60">
      <button
        type="button"
        onClick={() => onPlay(track)}
        className="relative h-14 w-24 shrink-0 overflow-hidden rounded-lg bg-muted"
      >
        <img src={track.artwork} alt="" className="h-full w-full object-cover" loading="lazy" />
        <span className="absolute inset-0 flex items-center justify-center bg-black/25">
          <Play className="h-5 w-5 text-white" fill="currentColor" />
        </span>
      </button>
      <button type="button" onClick={() => onPlay(track)} className="min-w-0 flex-1 text-left">
        <p className="line-clamp-2 text-sm font-medium">{track.title}</p>
        <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
      </button>
      <button
        type="button"
        onClick={() => onToggleSaved(track)}
        className="shrink-0 rounded-full p-2 text-muted-foreground hover:text-primary"
        aria-label={saved ? "Remove from library" : "Save to library"}
      >
        {saved ? <Check className="h-4 w-4" /> : <Bookmark className="h-4 w-4" />}
      </button>
      <a
        href={youtubeWatchUrl(track.videoId)}
        target="_blank"
        rel="noreferrer"
        className="shrink-0 rounded-full p-2 text-muted-foreground"
        aria-label="Open on YouTube"
      >
        <ExternalLink className="h-4 w-4" />
      </a>
    </div>
  );
}
