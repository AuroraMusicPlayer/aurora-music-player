import { Plus, Music4 } from "lucide-react";
import { AddMusicDialog } from "./AddMusicDialog";
import { Button } from "@/components/ui/button";

export function EmptyLibrary({ compact }: { compact?: boolean }) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 px-8 py-16 text-center">
      <div className="relative flex h-20 w-20 items-center justify-center rounded-3xl aurora-bg shadow-lg">
        <Music4 className="h-10 w-10 text-primary-foreground" />
      </div>
      <div>
        <h3 className="text-lg font-bold font-display">
          {compact ? "Nothing here yet" : "Your library is empty"}
        </h3>
        <p className="mx-auto mt-1 max-w-xs text-sm text-muted-foreground">
          Add songs from your device or paste a direct audio link to start listening.
        </p>
      </div>
      <AddMusicDialog>
        <Button size="lg" className="rounded-full">
          <Plus className="mr-2 h-4 w-4" /> Add music
        </Button>
      </AddMusicDialog>
    </div>
  );
}
