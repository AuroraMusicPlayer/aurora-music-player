import { useState } from "react";
import { motion } from "framer-motion";
import {
  ChevronDown,
  Heart,
  ListMusic,
  Pause,
  Play,
  Repeat,
  Repeat1,
  Shuffle,
  SkipBack,
  SkipForward,
  Moon,
  Gauge,
  Mic2,
  SlidersHorizontal,
} from "lucide-react";
import { Slider } from "@/components/ui/slider";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Artwork } from "./Artwork";
import { QueueSheet } from "./QueueSheet";
import { EqualizerSheet } from "./EqualizerSheet";
import { usePlayer } from "@/store/player";
import { byIds, formatTime } from "@/lib/selectors";
import { cn } from "@/lib/utils";

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
const SLEEP_OPTIONS = [5, 10, 15, 30, 45, 60];

export function FullPlayer() {
  const tracks = usePlayer((s) => s.tracks);
  const currentId = usePlayer((s) => s.currentId);
  const isPlaying = usePlayer((s) => s.isPlaying);
  const togglePlay = usePlayer((s) => s.togglePlay);
  const next = usePlayer((s) => s.next);
  const prev = usePlayer((s) => s.prev);
  const seek = usePlayer((s) => s.seek);
  const duration = usePlayer((s) => s.duration);
  const currentTime = usePlayer((s) => s.currentTime);
  const shuffle = usePlayer((s) => s.shuffle);
  const toggleShuffle = usePlayer((s) => s.toggleShuffle);
  const repeat = usePlayer((s) => s.repeat);
  const cycleRepeat = usePlayer((s) => s.cycleRepeat);
  const favorites = usePlayer((s) => s.favorites);
  const toggleFavorite = usePlayer((s) => s.toggleFavorite);
  const setPlayerOpen = usePlayer((s) => s.setPlayerOpen);
  const rate = usePlayer((s) => s.rate);
  const setRate = usePlayer((s) => s.setRate);
  const sleepTimerEnd = usePlayer((s) => s.sleepTimerEnd);
  const setSleepTimer = usePlayer((s) => s.setSleepTimer);

  const [queueOpen, setQueueOpen] = useState(false);
  const [eqOpen, setEqOpen] = useState(false);
  const [showLyrics, setShowLyrics] = useState(false);

  const track = currentId ? byIds(tracks, [currentId])[0] : undefined;
  if (!track) return null;
  const isFav = favorites.includes(track.id);

  return (
    <motion.div
      initial={{ y: "100%" }}
      animate={{ y: 0 }}
      exit={{ y: "100%" }}
      transition={{ type: "spring", stiffness: 300, damping: 34 }}
      drag="y"
      dragConstraints={{ top: 0, bottom: 0 }}
      dragElastic={{ top: 0, bottom: 0.5 }}
      onDragEnd={(_, info) => {
        if (info.offset.y > 140) setPlayerOpen(false);
      }}
      className="fixed inset-0 z-50 flex flex-col overflow-hidden"
    >
      {/* Blurred artwork background */}
      <div className="absolute inset-0 -z-10">
        {track.artwork ? (
          <img
            src={track.artwork}
            alt=""
            className="h-full w-full scale-125 object-cover blur-3xl"
          />
        ) : (
          <div className="aurora-bg h-full w-full" />
        )}
        <div className="absolute inset-0 bg-background/70 backdrop-blur-2xl" />
      </div>

      {/* Header */}
      <div className="flex items-center justify-between px-5 pt-5">
        <button
          aria-label="Close player"
          onClick={() => setPlayerOpen(false)}
          className="rounded-full p-2 transition-transform active:scale-90"
        >
          <ChevronDown className="h-6 w-6" />
        </button>
        <div className="text-center">
          <p className="text-[11px] uppercase tracking-widest text-muted-foreground">
            Now playing
          </p>
          <p className="max-w-[60vw] truncate text-xs font-medium">{track.album}</p>
        </div>
        <button
          aria-label="Queue"
          onClick={() => setQueueOpen(true)}
          className="rounded-full p-2 transition-transform active:scale-90"
        >
          <ListMusic className="h-6 w-6" />
        </button>
      </div>

      {/* Artwork / Lyrics */}
      <div className="flex flex-1 items-center justify-center px-8 py-4">
        {showLyrics && track.lyrics ? (
          <div className="h-full max-h-[55vh] w-full max-w-md overflow-y-auto rounded-3xl glass p-6">
            <p className="whitespace-pre-wrap text-center text-lg font-medium leading-relaxed">
              {track.lyrics}
            </p>
          </div>
        ) : (
          <motion.div
            layout
            className={cn(
              "aspect-square w-full max-w-sm overflow-hidden rounded-[2rem] shadow-2xl",
              isPlaying && "animate-spin-slow rounded-full",
            )}
            style={{ animationPlayState: isPlaying ? "running" : "paused" }}
          >
            <Artwork src={track.artwork} className="h-full w-full" rounded="rounded-[2rem]" />
          </motion.div>
        )}
      </div>

      {/* Track info + favorite */}
      <div className="flex items-center gap-3 px-8">
        <div className="min-w-0 flex-1">
          <h2 className="truncate text-2xl font-bold font-display">{track.title}</h2>
          <p className="truncate text-muted-foreground">{track.artist}</p>
        </div>
        <button
          aria-label="Favorite"
          onClick={() => toggleFavorite(track.id)}
          className="rounded-full p-2 transition-transform active:scale-125"
        >
          <Heart
            className={cn("h-7 w-7", isFav && "text-primary")}
            fill={isFav ? "currentColor" : "none"}
          />
        </button>
      </div>

      {/* Seek bar */}
      <div className="px-8 pt-4">
        <Slider
          value={[currentTime]}
          max={duration || track.duration || 1}
          step={1}
          onValueChange={([v]) => seek(v)}
        />
        <div className="mt-1.5 flex justify-between text-xs tabular-nums text-muted-foreground">
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration || track.duration)}</span>
        </div>
      </div>

      {/* Main controls */}
      <div className="flex items-center justify-between px-8 py-5">
        <button
          aria-label="Shuffle"
          onClick={toggleShuffle}
          className={cn("p-2 transition-colors", shuffle ? "text-primary" : "text-muted-foreground")}
        >
          <Shuffle className="h-5 w-5" />
        </button>
        <button aria-label="Previous" onClick={() => prev()} className="p-2 active:scale-90">
          <SkipBack className="h-8 w-8" fill="currentColor" />
        </button>
        <button
          aria-label={isPlaying ? "Pause" : "Play"}
          onClick={togglePlay}
          className="flex h-16 w-16 items-center justify-center rounded-full aurora-bg text-primary-foreground shadow-lg transition-transform active:scale-90"
        >
          {isPlaying ? (
            <Pause className="h-8 w-8" fill="currentColor" />
          ) : (
            <Play className="ml-0.5 h-8 w-8" fill="currentColor" />
          )}
        </button>
        <button aria-label="Next" onClick={() => next()} className="p-2 active:scale-90">
          <SkipForward className="h-8 w-8" fill="currentColor" />
        </button>
        <button
          aria-label="Repeat"
          onClick={cycleRepeat}
          className={cn(
            "p-2 transition-colors",
            repeat !== "off" ? "text-primary" : "text-muted-foreground",
          )}
        >
          {repeat === "one" ? <Repeat1 className="h-5 w-5" /> : <Repeat className="h-5 w-5" />}
        </button>
      </div>

      {/* Secondary action bar */}
      <div className="flex items-center justify-around border-t border-border/50 px-4 py-3 pb-6">
        {/* Sleep timer */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              className={cn(
                "flex flex-col items-center gap-1 text-[11px]",
                sleepTimerEnd ? "text-primary" : "text-muted-foreground",
              )}
            >
              <Moon className="h-5 w-5" />
              Sleep
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start">
            <DropdownMenuLabel>Sleep timer</DropdownMenuLabel>
            {SLEEP_OPTIONS.map((m) => (
              <DropdownMenuItem key={m} onClick={() => setSleepTimer(m)}>
                {m} minutes
              </DropdownMenuItem>
            ))}
            {sleepTimerEnd && (
              <DropdownMenuItem onClick={() => setSleepTimer(null)}>Turn off</DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>

        {/* Speed */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              className={cn(
                "flex flex-col items-center gap-1 text-[11px]",
                rate !== 1 ? "text-primary" : "text-muted-foreground",
              )}
            >
              <Gauge className="h-5 w-5" />
              {rate}×
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="center">
            <DropdownMenuLabel>Playback speed</DropdownMenuLabel>
            {SPEEDS.map((sp) => (
              <DropdownMenuItem key={sp} onClick={() => setRate(sp)}>
                {sp}×
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>

        {/* Lyrics — only when embedded lyrics exist */}
        {track.lyrics && (
          <button
            onClick={() => setShowLyrics((v) => !v)}
            className={cn(
              "flex flex-col items-center gap-1 text-[11px]",
              showLyrics ? "text-primary" : "text-muted-foreground",
            )}
          >
            <Mic2 className="h-5 w-5" />
            Lyrics
          </button>
        )}

        {/* Equalizer */}
        <button
          onClick={() => setEqOpen(true)}
          className="flex flex-col items-center gap-1 text-[11px] text-muted-foreground"
        >
          <SlidersHorizontal className="h-5 w-5" />
          EQ
        </button>
      </div>

      <QueueSheet open={queueOpen} onOpenChange={setQueueOpen} />
      <EqualizerSheet open={eqOpen} onOpenChange={setEqOpen} />
    </motion.div>
  );
}
