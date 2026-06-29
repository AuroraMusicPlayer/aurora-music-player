import { createFileRoute, Link } from "@tanstack/react-router";
import { Plus, Play, Heart, Clock, Flame, Disc3, Mic2, Tag, FolderOpen } from "lucide-react";
import { usePlayer } from "@/store/player";
import {
  byIds,
  getAlbums,
  getArtists,
  getGenres,
  mostPlayed,
  recentlyPlayed,
} from "@/lib/selectors";
import { AddMusicDialog } from "@/components/AddMusicDialog";
import { EmptyLibrary } from "@/components/EmptyLibrary";
import { MediaCard } from "@/components/MediaCard";
import { Shelf } from "@/components/Shelf";
import { Artwork } from "@/components/Artwork";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Aurora Music — Your Library" },
      {
        name: "description",
        content: "Your personal music dashboard: recently played, most played, favorites and more.",
      },
    ],
  }),
  component: Home,
});

function greeting() {
  const h = new Date().getHours();
  if (h < 12) return "Good morning";
  if (h < 18) return "Good afternoon";
  return "Good evening";
}

function Home() {
  const hydrated = usePlayer((s) => s.hydrated);
  const tracks = usePlayer((s) => s.tracks);
  const stats = usePlayer((s) => s.stats);
  const favorites = usePlayer((s) => s.favorites);
  const playContext = usePlayer((s) => s.playContext);
  const currentId = usePlayer((s) => s.currentId);
  const setPlayerOpen = usePlayer((s) => s.setPlayerOpen);

  const recent = recentlyPlayed(tracks, stats);
  const most = mostPlayed(tracks, stats);
  const favTracks = byIds(tracks, favorites);
  const albums = getAlbums(tracks).slice(0, 12);
  const artists = getArtists(tracks).slice(0, 12);
  const genres = getGenres(tracks).slice(0, 12);

  const resume = currentId ? byIds(tracks, [currentId])[0] : recent[0];

  return (
    <div className="relative space-y-7 pb-6">
      {/* Hero header */}
      <header className="aurora-glow relative px-4 pt-6">
        <div className="relative flex items-center justify-between">
          <div>
            <p className="text-sm text-muted-foreground">{greeting()}</p>
            <h1 className="text-3xl font-extrabold tracking-tight aurora-text font-display">
              Aurora Music
            </h1>
          </div>
          <AddMusicDialog>
            <Button size="icon" className="h-11 w-11 rounded-full shadow-md">
              <Plus className="h-5 w-5" />
            </Button>
          </AddMusicDialog>
        </div>
      </header>

      {!hydrated ? (
        <div className="space-y-4 px-4">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-40 animate-pulse rounded-2xl bg-muted" />
          ))}
        </div>
      ) : tracks.length === 0 ? (
        <EmptyLibrary />
      ) : (
        <>
          {/* Continue listening */}
          {resume && (
            <section className="px-4">
              <h2 className="mb-3 text-lg font-bold font-display">Continue listening</h2>
              <button
                onClick={() => {
                  if (currentId) setPlayerOpen(true);
                  else playContext([resume.id]);
                }}
                className="glass flex w-full items-center gap-4 rounded-2xl p-3 text-left transition-transform active:scale-[0.98]"
              >
                <Artwork src={resume.artwork} className="h-20 w-20" rounded="rounded-xl" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-base font-semibold">{resume.title}</p>
                  <p className="truncate text-sm text-muted-foreground">{resume.artist}</p>
                </div>
                <span className="flex h-12 w-12 items-center justify-center rounded-full aurora-bg text-primary-foreground shadow">
                  <Play className="ml-0.5 h-6 w-6" fill="currentColor" />
                </span>
              </button>
            </section>
          )}

          {/* Quick access tiles */}
          <div className="grid grid-cols-2 gap-3 px-4">
            <QuickTile to="/library" icon={Clock} label="Recently added" tint="recent" />
            <QuickTile to="/playlists" icon={Heart} label="Favorites" tint="fav" search />
          </div>

          {recent.length > 0 && (
            <Shelf title="Recently played">
              {recent.slice(0, 12).map((t) => (
                <MediaCard
                  key={t.id}
                  to="/album/$id"
                  params={{ id: getAlbums(tracks).find((a) => a.trackIds.includes(t.id))?.id ?? "" }}
                  title={t.title}
                  subtitle={t.artist}
                  artwork={t.artwork}
                />
              ))}
            </Shelf>
          )}

          {most.length > 0 && (
            <Shelf title="Most played">
              {most.slice(0, 12).map((t) => (
                <MediaCard
                  key={t.id}
                  to="/collection/$type/$id"
                  params={{ type: "most", id: "all" }}
                  title={t.title}
                  subtitle={`${stats[t.id]?.count ?? 0} plays`}
                  artwork={t.artwork}
                />
              ))}
            </Shelf>
          )}

          {favTracks.length > 0 && (
            <Shelf
              title="Favorites"
              action={
                <Link to="/collection/$type/$id" params={{ type: "favorites", id: "all" }} className="text-xs font-medium text-primary">
                  See all
                </Link>
              }
            >
              {favTracks.slice(0, 12).map((t) => (
                <MediaCard
                  key={t.id}
                  to="/collection/$type/$id"
                  params={{ type: "favorites", id: "all" }}
                  title={t.title}
                  subtitle={t.artist}
                  artwork={t.artwork}
                />
              ))}
            </Shelf>
          )}

          {albums.length > 0 && (
            <Shelf
              title="Albums"
              action={<SectionLink label="Albums" />}
            >
              {albums.map((a) => (
                <MediaCard
                  key={a.id}
                  to="/album/$id"
                  params={{ id: a.id }}
                  title={a.name}
                  subtitle={a.artist}
                  artwork={a.artwork}
                />
              ))}
            </Shelf>
          )}

          {artists.length > 0 && (
            <Shelf title="Artists">
              {artists.map((a) => (
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
            </Shelf>
          )}

          {genres.length > 0 && (
            <Shelf title="Genres">
              {genres.map((g) => (
                <MediaCard
                  key={g.id}
                  to="/collection/$type/$id"
                  params={{ type: "genre", id: g.id }}
                  title={g.name}
                  subtitle={g.subtitle}
                  artwork={g.artwork}
                />
              ))}
            </Shelf>
          )}
        </>
      )}
    </div>
  );
}

function SectionLink({ label }: { label: string }) {
  return (
    <Link to="/library" className="text-xs font-medium text-primary">
      {label}
    </Link>
  );
}

function QuickTile({
  to,
  icon: Icon,
  label,
}: {
  to: string;
  icon: typeof Clock;
  label: string;
  tint?: string;
  search?: boolean;
}) {
  return (
    <Link
      to={to}
      className="glass flex items-center gap-3 rounded-2xl p-4 transition-transform active:scale-95"
    >
      <span className="flex h-10 w-10 items-center justify-center rounded-xl aurora-bg text-primary-foreground">
        <Icon className="h-5 w-5" />
      </span>
      <span className="text-sm font-semibold">{label}</span>
    </Link>
  );
}

// Re-export unused icons to keep imports tidy if referenced later.
void Disc3;
void Mic2;
void Tag;
void FolderOpen;
void Flame;
