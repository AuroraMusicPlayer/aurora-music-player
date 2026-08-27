import { useEffect, useMemo } from "react";
import { Bookmark, Check, ExternalLink, X } from "lucide-react";
import { toast } from "sonner";

import { onLocalPlayback } from "@/lib/playbackBus";
import { youtubeMusicUrl } from "@/lib/youtube";
import { useOnline } from "@/store/online";

/**
 * Route-independent visible YouTube player. Keeping this mounted lets a song
 * continue when the user navigates around Aurora without hiding the provider.
 */
export function OnlinePlayerDock() {
  const current = useOnline((state) => state.current);
  const saved = useOnline((state) => state.saved);
  const saveTrack = useOnline((state) => state.saveTrack);
  const removeSaved = useOnline((state) => state.removeSaved);
  const stop = useOnline((state) => state.stop);
  const isSaved = useMemo(
    () => Boolean(current && saved.some((track) => track.videoId === current.videoId)),
    [current, saved],
  );

  useEffect(() => onLocalPlayback(stop), [stop]);

  if (!current) return null;

  function toggleSaved() {
    if (!current) return;
    if (isSaved) {
      removeSaved(current.videoId);
      toast.success("Removed from online library");
    } else {
      saveTrack(current);
      toast.success("Saved to online library");
    }
  }

  return (
    <section className="shrink-0 border-t border-border bg-card shadow-[0_-8px_30px_rgba(0,0,0,0.18)]">
      <div className="mx-auto flex max-h-[42dvh] max-w-3xl flex-col sm:flex-row">
        <div className="relative min-h-[200px] flex-1 bg-black sm:max-w-sm">
          <iframe
            key={current.videoId}
            src={`https://www.youtube.com/embed/${encodeURIComponent(
              current.videoId,
            )}?autoplay=1&playsinline=1&rel=0`}
            title={current.title}
            allow="autoplay; encrypted-media; fullscreen"
            allowFullScreen
            className="absolute inset-0 h-full w-full border-0"
          />
        </div>
        <div className="flex min-w-0 items-center gap-2 p-2.5 sm:w-64 sm:flex-col sm:items-stretch sm:justify-center sm:p-4">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold">{current.title}</p>
            <p className="truncate text-xs text-muted-foreground">{current.artist}</p>
          </div>
          <div className="flex items-center justify-end gap-1">
            <button
              type="button"
              aria-label={isSaved ? "Remove from online library" : "Save to online library"}
              onClick={toggleSaved}
              className="rounded-full p-2 text-primary hover:bg-accent"
            >
              {isSaved ? <Check className="h-5 w-5" /> : <Bookmark className="h-5 w-5" />}
            </button>
            <a
              href={youtubeMusicUrl(current.videoId)}
              target="_blank"
              rel="noreferrer"
              className="rounded-full p-2 text-muted-foreground hover:bg-accent"
              aria-label="Open in YouTube Music"
            >
              <ExternalLink className="h-5 w-5" />
            </a>
            <button
              type="button"
              aria-label="Close online player"
              onClick={stop}
              className="rounded-full p-2 text-muted-foreground hover:bg-accent"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
