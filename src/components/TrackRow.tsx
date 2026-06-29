import { Heart, MoreVertical, Play, Pause, ListPlus, ListEnd, Trash2, Plus } from "lucide-react";
import { Artwork } from "./Artwork";
import { usePlayer } from "@/store/player";
import { formatTime } from "@/lib/selectors";
import type { Track } from "@/lib/types";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

interface TrackRowProps {
  track: Track;
  context: string[];
  index?: number;
  onRemoveFromPlaylist?: (id: string) => void;
}

export function TrackRow({ track, context, index, onRemoveFromPlaylist }: TrackRowProps) {
  const playTrack = usePlayer((s) => s.playTrack);
  const currentId = usePlayer((s) => s.currentId);
  const isPlaying = usePlayer((s) => s.isPlaying);
  const togglePlay = usePlayer((s) => s.togglePlay);
  const favorites = usePlayer((s) => s.favorites);
  const toggleFavorite = usePlayer((s) => s.toggleFavorite);
  const playlists = usePlayer((s) => s.playlists);
  const addToQueue = usePlayer((s) => s.addToQueue);
  const playNextInQueue = usePlayer((s) => s.playNextInQueue);
  const addToPlaylist = usePlayer((s) => s.addToPlaylist);
  const createPlaylist = usePlayer((s) => s.createPlaylist);
  const removeTrack = usePlayer((s) => s.removeTrack);

  const isCurrent = currentId === track.id;
  const isFav = favorites.includes(track.id);

  return (
    <div
      className={cn(
        "group flex items-center gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-accent/60 cursor-pointer",
        isCurrent && "bg-accent/70",
      )}
      onClick={() => (isCurrent ? togglePlay() : playTrack(track.id, context))}
    >
      <div className="relative">
        <Artwork src={track.artwork} className="h-12 w-12" rounded="rounded-lg" />
        <div
          className={cn(
            "absolute inset-0 flex items-center justify-center rounded-lg bg-black/40 opacity-0 transition-opacity",
            "group-hover:opacity-100",
            isCurrent && "opacity-100",
          )}
        >
          {isCurrent && isPlaying ? (
            <Pause className="h-5 w-5 text-white" fill="currentColor" />
          ) : (
            <Play className="h-5 w-5 text-white" fill="currentColor" />
          )}
        </div>
      </div>

      <div className="min-w-0 flex-1">
        <p className={cn("truncate text-sm font-medium", isCurrent && "text-primary")}>
          {track.title}
        </p>
        <p className="truncate text-xs text-muted-foreground">
          {track.artist} {track.album !== "Unknown Album" ? `· ${track.album}` : ""}
        </p>
      </div>

      {track.duration > 0 && (
        <span className="hidden text-xs tabular-nums text-muted-foreground sm:block">
          {formatTime(track.duration)}
        </span>
      )}

      <button
        aria-label="Toggle favorite"
        onClick={(e) => {
          e.stopPropagation();
          toggleFavorite(track.id);
        }}
        className="rounded-full p-1.5 text-muted-foreground transition-colors hover:text-primary"
      >
        <Heart
          className={cn("h-4 w-4 transition-transform active:scale-125", isFav && "text-primary")}
          fill={isFav ? "currentColor" : "none"}
        />
      </button>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            aria-label="Track options"
            onClick={(e) => e.stopPropagation()}
            className="rounded-full p-1.5 text-muted-foreground transition-colors hover:text-foreground"
          >
            <MoreVertical className="h-4 w-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" onClick={(e) => e.stopPropagation()} className="w-52">
          <DropdownMenuItem
            onClick={() => {
              playNextInQueue(track.id);
              toast.success("Playing next");
            }}
          >
            <ListEnd className="mr-2 h-4 w-4" /> Play next
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => {
              addToQueue([track.id]);
              toast.success("Added to queue");
            }}
          >
            <ListPlus className="mr-2 h-4 w-4" /> Add to queue
          </DropdownMenuItem>
          <DropdownMenuSub>
            <DropdownMenuSubTrigger>
              <Plus className="mr-2 h-4 w-4" /> Add to playlist
            </DropdownMenuSubTrigger>
            <DropdownMenuSubContent>
              <DropdownMenuItem
                onClick={() => {
                  const name = prompt("Playlist name");
                  if (name) {
                    createPlaylist(name, [track.id]);
                    toast.success(`Created "${name}"`);
                  }
                }}
              >
                <Plus className="mr-2 h-4 w-4" /> New playlist…
              </DropdownMenuItem>
              {playlists.length > 0 && <DropdownMenuSeparator />}
              {playlists.map((p) => (
                <DropdownMenuItem
                  key={p.id}
                  onClick={() => {
                    addToPlaylist(p.id, [track.id]);
                    toast.success(`Added to ${p.name}`);
                  }}
                >
                  {p.name}
                </DropdownMenuItem>
              ))}
            </DropdownMenuSubContent>
          </DropdownMenuSub>
          <DropdownMenuItem onClick={() => toggleFavorite(track.id)}>
            <Heart className="mr-2 h-4 w-4" /> {isFav ? "Remove favorite" : "Add to favorites"}
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          {onRemoveFromPlaylist && (
            <DropdownMenuItem onClick={() => onRemoveFromPlaylist(track.id)}>
              <Trash2 className="mr-2 h-4 w-4" /> Remove from playlist
            </DropdownMenuItem>
          )}
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={() => {
              void removeTrack(track.id);
              toast.success("Removed from library");
            }}
          >
            <Trash2 className="mr-2 h-4 w-4" /> Delete from library
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      {typeof index === "number" && <span className="sr-only">{index}</span>}
    </div>
  );
}
