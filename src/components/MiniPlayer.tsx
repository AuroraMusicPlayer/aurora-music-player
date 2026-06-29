import { motion } from "framer-motion";
import { Play, Pause, SkipForward, X } from "lucide-react";
import { Artwork } from "./Artwork";
import { usePlayer } from "@/store/player";
import { byIds } from "@/lib/selectors";

export function MiniPlayer() {
  const tracks = usePlayer((s) => s.tracks);
  const currentId = usePlayer((s) => s.currentId);
  const isPlaying = usePlayer((s) => s.isPlaying);
  const togglePlay = usePlayer((s) => s.togglePlay);
  const next = usePlayer((s) => s.next);
  const dismiss = usePlayer((s) => s.dismiss);
  const setPlayerOpen = usePlayer((s) => s.setPlayerOpen);
  const duration = usePlayer((s) => s.duration);
  const currentTime = usePlayer((s) => s.currentTime);

  const track = currentId ? byIds(tracks, [currentId])[0] : undefined;
  if (!track) return null;

  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  return (
    <motion.div
      layout
      drag="x"
      dragConstraints={{ left: 0, right: 0 }}
      dragElastic={0.6}
      onDragEnd={(_, info) => {
        if (Math.abs(info.offset.x) > 120) dismiss();
      }}
      initial={{ y: 80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: 80, opacity: 0 }}
      transition={{ type: "spring", stiffness: 320, damping: 32 }}
      className="glass mx-2 overflow-hidden rounded-2xl shadow-lg"
    >
      <div className="flex items-center gap-3 p-2">
        <button
          className="flex min-w-0 flex-1 items-center gap-3 text-left"
          onClick={() => setPlayerOpen(true)}
        >
          <Artwork src={track.artwork} className="h-11 w-11" rounded="rounded-lg" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{track.title}</p>
            <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
          </div>
        </button>
        <button
          aria-label={isPlaying ? "Pause" : "Play"}
          onClick={togglePlay}
          className="rounded-full p-2 text-foreground transition-transform active:scale-90"
        >
          {isPlaying ? (
            <Pause className="h-5 w-5" fill="currentColor" />
          ) : (
            <Play className="h-5 w-5" fill="currentColor" />
          )}
        </button>
        <button
          aria-label="Next"
          onClick={() => next()}
          className="rounded-full p-2 text-foreground transition-transform active:scale-90"
        >
          <SkipForward className="h-5 w-5" fill="currentColor" />
        </button>
        <button
          aria-label="Dismiss"
          onClick={dismiss}
          className="rounded-full p-2 text-muted-foreground transition-transform active:scale-90"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
      <div className="h-0.5 w-full bg-border">
        <div className="h-full aurora-bg transition-[width]" style={{ width: `${progress}%` }} />
      </div>
    </motion.div>
  );
}
