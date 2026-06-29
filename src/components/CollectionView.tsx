import { useRouter } from "@tanstack/react-router";
import { ChevronLeft, Play, Shuffle, Clock } from "lucide-react";
import { Artwork } from "./Artwork";
import { TrackRow } from "./TrackRow";
import { Button } from "@/components/ui/button";
import { usePlayer } from "@/store/player";
import { formatTime } from "@/lib/selectors";
import type { Track } from "@/lib/types";
import type { ReactNode } from "react";

interface CollectionViewProps {
  title: string;
  subtitle: string;
  artwork: string | null;
  tracks: Track[];
  round?: boolean;
  actions?: ReactNode;
  onRemoveTrack?: (id: string) => void;
}

export function CollectionView({
  title,
  subtitle,
  artwork,
  tracks,
  round,
  actions,
  onRemoveTrack,
}: CollectionViewProps) {
  const router = useRouter();
  const playContext = usePlayer((s) => s.playContext);
  const toggleShuffle = usePlayer((s) => s.toggleShuffle);
  const shuffle = usePlayer((s) => s.shuffle);

  const ids = tracks.map((t) => t.id);
  const totalSec = tracks.reduce((acc, t) => acc + t.duration, 0);

  function playAll() {
    if (ids.length) playContext(ids, 0);
  }

  function shuffleAll() {
    if (!ids.length) return;
    if (!shuffle) toggleShuffle();
    playContext(ids, Math.floor(Math.random() * ids.length));
  }

  return (
    <div className="pb-6">
      {/* Header */}
      <div className="aurora-glow relative flex flex-col items-center gap-4 px-4 pb-5 pt-5 text-center">
        <button
          onClick={() => router.history.back()}
          aria-label="Back"
          className="absolute left-3 top-5 rounded-full glass p-2"
        >
          <ChevronLeft className="h-5 w-5" />
        </button>
        <Artwork
          src={artwork}
          className="h-44 w-44 shadow-xl"
          rounded={round ? "rounded-full" : "rounded-3xl"}
        />
        <div className="relative">
          <h1 className="text-2xl font-extrabold font-display">{title}</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">{subtitle}</p>
          {totalSec > 0 && (
            <p className="mt-1 flex items-center justify-center gap-1 text-xs text-muted-foreground">
              <Clock className="h-3 w-3" /> {formatTime(totalSec)}
            </p>
          )}
        </div>
        <div className="flex gap-3">
          <Button onClick={playAll} className="rounded-full px-6" disabled={!ids.length}>
            <Play className="mr-1.5 h-4 w-4" fill="currentColor" /> Play
          </Button>
          <Button
            onClick={shuffleAll}
            variant="secondary"
            className="rounded-full px-6"
            disabled={!ids.length}
          >
            <Shuffle className="mr-1.5 h-4 w-4" /> Shuffle
          </Button>
        </div>
        {actions}
      </div>

      {/* Tracks */}
      <div className="space-y-0.5 px-2">
        {tracks.map((t, i) => (
          <TrackRow
            key={t.id}
            track={t}
            context={ids}
            index={i}
            onRemoveFromPlaylist={onRemoveTrack}
          />
        ))}
      </div>
    </div>
  );
}
