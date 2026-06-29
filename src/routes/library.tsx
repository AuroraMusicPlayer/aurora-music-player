import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { Plus } from "lucide-react";
import { usePlayer } from "@/store/player";
import {
  getAlbums,
  getArtists,
  getFolders,
  getGenres,
  getYears,
  recentlyAdded,
} from "@/lib/selectors";
import { TrackRow } from "@/components/TrackRow";
import { MediaCard } from "@/components/MediaCard";
import { EmptyLibrary } from "@/components/EmptyLibrary";
import { AddMusicDialog } from "@/components/AddMusicDialog";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/library")({
  head: () => ({ meta: [{ title: "Library — Aurora Music" }] }),
  component: LibraryPage,
});

const TABS = ["Songs", "Albums", "Artists", "Genres", "Folders", "Years"] as const;
type Tab = (typeof TABS)[number];

function LibraryPage() {
  const [tab, setTab] = useState<Tab>("Songs");
  const tracks = usePlayer((s) => s.tracks);
  const hydrated = usePlayer((s) => s.hydrated);

  if (hydrated && tracks.length === 0) {
    return (
      <div className="pt-6">
        <h1 className="px-4 text-2xl font-extrabold font-display">Library</h1>
        <EmptyLibrary />
      </div>
    );
  }

  const songs = recentlyAdded(tracks);

  return (
    <div className="space-y-4 pb-6">
      <header className="sticky top-0 z-10 space-y-3 bg-background/80 px-4 pb-2 pt-6 backdrop-blur-xl">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-extrabold font-display">Library</h1>
          <AddMusicDialog>
            <Button size="icon" variant="secondary" className="h-9 w-9 rounded-full">
              <Plus className="h-5 w-5" />
            </Button>
          </AddMusicDialog>
        </div>
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          {TABS.map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn(
                "shrink-0 rounded-full px-4 py-1.5 text-sm font-medium transition-colors",
                tab === t ? "aurora-bg text-primary-foreground" : "glass text-muted-foreground",
              )}
            >
              {t}
            </button>
          ))}
        </div>
      </header>

      {tab === "Songs" && (
        <div className="space-y-0.5 px-2">
          {songs.map((t, i) => (
            <TrackRow key={t.id} track={t} context={songs.map((x) => x.id)} index={i} />
          ))}
        </div>
      )}

      {tab === "Albums" && (
        <Grid>
          {getAlbums(tracks).map((a) => (
            <MediaCard
              key={a.id}
              to="/album/$id"
              params={{ id: a.id }}
              title={a.name}
              subtitle={a.artist}
              artwork={a.artwork}
            />
          ))}
        </Grid>
      )}

      {tab === "Artists" && (
        <Grid>
          {getArtists(tracks).map((a) => (
            <MediaCard
              key={a.id}
              to="/collection/$type/$id"
              params={{ type: "artist", id: a.id }}
              title={a.name}
              subtitle={a.subtitle}
              artwork={a.artwork}
              round
            />
          ))}
        </Grid>
      )}

      {tab === "Genres" && (
        <Grid>
          {getGenres(tracks).map((g) => (
            <MediaCard
              key={g.id}
              to="/collection/$type/$id"
              params={{ type: "genre", id: g.id }}
              title={g.name}
              subtitle={g.subtitle}
              artwork={g.artwork}
            />
          ))}
        </Grid>
      )}

      {tab === "Folders" && (
        <Grid>
          {getFolders(tracks).map((f) => (
            <MediaCard
              key={f.id}
              to="/collection/$type/$id"
              params={{ type: "folder", id: f.id }}
              title={f.name}
              subtitle={f.subtitle}
              artwork={f.artwork}
            />
          ))}
        </Grid>
      )}

      {tab === "Years" && (
        <Grid>
          {getYears(tracks).map((y) => (
            <MediaCard
              key={y.id}
              to="/collection/$type/$id"
              params={{ type: "year", id: y.id }}
              title={y.name}
              subtitle={y.subtitle}
              artwork={y.artwork}
            />
          ))}
        </Grid>
      )}
    </div>
  );
}

function Grid({ children }: { children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-2 gap-x-4 gap-y-5 px-4 sm:grid-cols-3">
      {/* MediaCard has fixed width; relax it within grid */}
      <div className="contents [&_a]:w-full">{children}</div>
    </div>
  );
}
