import { GripVertical, Trash2, X, ListMusic } from "lucide-react";
import { Reorder } from "framer-motion";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Artwork } from "./Artwork";
import { usePlayer } from "@/store/player";
import { byIds } from "@/lib/selectors";
import { cn } from "@/lib/utils";

export function QueueSheet({ open, onOpenChange }: { open: boolean; onOpenChange: (v: boolean) => void }) {
  const tracks = usePlayer((s) => s.tracks);
  const queue = usePlayer((s) => s.queue);
  const queueIndex = usePlayer((s) => s.queueIndex);
  const reorderQueue = usePlayer((s) => s.reorderQueue);
  const removeFromQueue = usePlayer((s) => s.removeFromQueue);
  const clearQueue = usePlayer((s) => s.clearQueue);
  const playContext = usePlayer((s) => s.playContext);

  const queueTracks = byIds(tracks, queue);

  function handleReorder(newOrder: typeof queueTracks) {
    // Translate the reordered track list back into index moves.
    const newIds = newOrder.map((t) => t.id);
    // Find first differing position and apply a single move.
    for (let i = 0; i < newIds.length; i++) {
      if (newIds[i] !== queue[i]) {
        const from = queue.indexOf(newIds[i]);
        reorderQueue(from, i);
        return;
      }
    }
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="h-[80vh] rounded-t-3xl p-0">
        <SheetHeader className="flex flex-row items-center justify-between px-5 pt-5">
          <SheetTitle className="flex items-center gap-2 font-display">
            <ListMusic className="h-5 w-5" /> Up next
          </SheetTitle>
          <button
            onClick={clearQueue}
            className="text-xs font-medium text-muted-foreground hover:text-destructive"
          >
            Clear
          </button>
        </SheetHeader>

        {queueTracks.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 text-muted-foreground">
            <ListMusic className="h-10 w-10 opacity-40" />
            <p className="text-sm">Your queue is empty</p>
          </div>
        ) : (
          <Reorder.Group
            axis="y"
            values={queueTracks}
            onReorder={handleReorder}
            className="h-full space-y-1 overflow-y-auto px-3 pb-6"
          >
            {queueTracks.map((track, i) => (
              <Reorder.Item
                key={track.id}
                value={track}
                className={cn(
                  "flex items-center gap-2 rounded-xl bg-card/60 px-2 py-2",
                  i === queueIndex && "bg-accent",
                )}
              >
                <GripVertical className="h-4 w-4 shrink-0 cursor-grab text-muted-foreground" />
                <button
                  className="flex min-w-0 flex-1 items-center gap-3 text-left"
                  onClick={() => playContext(queue, i)}
                >
                  <Artwork src={track.artwork} className="h-10 w-10" rounded="rounded-md" />
                  <div className="min-w-0">
                    <p
                      className={cn(
                        "truncate text-sm font-medium",
                        i === queueIndex && "text-primary",
                      )}
                    >
                      {track.title}
                    </p>
                    <p className="truncate text-xs text-muted-foreground">{track.artist}</p>
                  </div>
                </button>
                <button
                  aria-label="Remove from queue"
                  onClick={() => removeFromQueue(i)}
                  className="rounded-full p-1.5 text-muted-foreground hover:text-destructive"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </Reorder.Item>
            ))}
          </Reorder.Group>
        )}
        <button
          onClick={() => onOpenChange(false)}
          aria-label="Close"
          className="absolute right-4 top-5 hidden"
        >
          <X />
        </button>
      </SheetContent>
    </Sheet>
  );
}
