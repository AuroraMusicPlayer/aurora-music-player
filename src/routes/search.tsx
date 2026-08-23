import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Search as SearchIcon, X } from "lucide-react";
import { usePlayer } from "@/store/player";
import {
  byIds,
  getAlbums,
  getArtists,
  getFolders,
  getGenres,
  searchTracks,
} from "@/lib/selectors";
import { TrackRow } from "@/components/TrackRow";
import { MediaCard } from "@/components/MediaCard";
import { Shelf } from "@/components/Shelf";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { YouTubePlayer } from "@/components/YouTubePlayer";

export const Route = createFileRoute("/search")({
  head: () => ({ meta: [{ title: "Search — Aurora Music" }] }),
  component: SearchPage,
});

function SearchPage() {
  const [q, setQ] = useState("");
  const tracks = usePlayer((s) => s.tracks);
  const playlists = usePlayer((s) => s.playlists);

  const results = useMemo(() => {
    const query = q.trim().toLowerCase();
    if (!query) return null;
    return {
      songs: searchTracks(tracks, q),
      albums: getAlbums(tracks).filter(
        (a) => a.name.toLowerCase().includes(query) || a.artist.toLowerCase().includes(query),
      ),
      artists: getArtists(tracks).filter((a) => a.name.toLowerCase().includes(query)),
      genres: getGenres(tracks).filter((g) => g.name.toLowerCase().includes(query)),
      folders: getFolders(tracks).filter((f) => f.name.toLowerCase().includes(query)),
      playlists: playlists.filter((p) => p.name.toLowerCase().includes(query)),
    };
  }, [q, tracks, playlists]);

  const empty =
    results &&
    results.songs.length === 0 &&
    results.albums.length === 0 &&
    results.artists.length === 0 &&
    results.genres.length === 0 &&
    results.folders.length === 0 &&
    results.playlists.length === 0;

  return (
    <Tabs defaultValue="library" className="flex flex-col">
      <header className="sticky top-0 z-10 bg-background/80 px-4 pb-2 pt-6 backdrop-blur-xl space-y-3">
        <h1 className="text-2xl font-extrabold font-display">Search</h1>
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="library">Library</TabsTrigger>
          <TabsTrigger value="youtube">YouTube</TabsTrigger>
        </TabsList>
      </header>

      {/* Library tab */}
      <TabsContent value="library" className="space-y-5 pb-6 mt-0">
        <div className="px-4 pt-2">
          <div className="glass flex items-center gap-2 rounded-2xl px-4 py-3">
            <SearchIcon className="h-5 w-5 text-muted-foreground" />
            <input
              autoFocus
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Songs, artists, albums, genres…"
              className="w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
            />
            {q && (
              <button onClick={() => setQ("")} aria-label="Clear">
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            )}
          </div>
        </div>

        {!results && (
          <p className="px-4 text-sm text-muted-foreground">
            Start typing to instantly find anything in your library.
          </p>
        )}

        {empty && (
          <p className="px-4 text-sm text-muted-foreground">No results for "{q}".</p>
        )}

        {results && results.artists.length > 0 && (
          <Shelf title="Artists">
            {results.artists.slice(0, 12).map((a) => (
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

        {results && results.albums.length > 0 && (
          <Shelf title="Albums">
            {results.albums.slice(0, 12).map((a) => (
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

        {results && results.playlists.length > 0 && (
          <Shelf title="Playlists">
            {results.playlists.slice(0, 12).map((p) => (
              <MediaCard
                key={p.id}
                to="/collection/$type/$id"
                params={{ type: "playlist", id: p.id }}
                title={p.name}
                subtitle={`${p.trackIds.length} songs`}
                artwork={byIds(tracks, p.trackIds)[0]?.artwork ?? null}
              />
            ))}
          </Shelf>
        )}

        {results && (results.genres.length > 0 || results.folders.length > 0) && (
          <Shelf title="Genres & Folders">
            {results.genres.slice(0, 8).map((g) => (
              <MediaCard
                key={g.id}
                to="/collection/$type/$id"
                params={{ type: "genre", id: g.id }}
                title={g.name}
                subtitle={g.subtitle}
                artwork={g.artwork}
              />
            ))}
            {results.folders.slice(0, 8).map((f) => (
              <MediaCard
                key={f.id}
                to="/collection/$type/$id"
                params={{ type: "folder", id: f.id }}
                title={f.name}
                subtitle={f.subtitle}
                artwork={f.artwork}
              />
            ))}
          </Shelf>
        )}

        {results && results.songs.length > 0 && (
          <section className="space-y-1 px-2">
            <h2 className="px-2 text-lg font-bold font-display">Songs</h2>
            {results.songs.slice(0, 50).map((t, i) => (
              <TrackRow key={t.id} track={t} context={results.songs.map((x) => x.id)} index={i} />
            ))}
          </section>
        )}
      </TabsContent>

      {/* YouTube tab */}
      <TabsContent value="youtube" className="mt-0">
        <YouTubePlayer />
      </TabsContent>
    </Tabs>
  );
}
