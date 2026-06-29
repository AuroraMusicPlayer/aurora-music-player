import { createFileRoute } from "@tanstack/react-router";
import { usePlayer } from "@/store/player";
import { byIds, getAlbums } from "@/lib/selectors";
import { CollectionView } from "@/components/CollectionView";

export const Route = createFileRoute("/album/$id")({
  component: AlbumPage,
});

function AlbumPage() {
  const { id } = Route.useParams();
  const tracks = usePlayer((s) => s.tracks);
  const album = getAlbums(tracks).find((a) => a.id === id);

  if (!album) {
    return <div className="p-8 text-center text-sm text-muted-foreground">Album not found.</div>;
  }

  const albumTracks = byIds(tracks, album.trackIds);
  const subtitle = [album.artist, album.year ? String(album.year) : null, `${albumTracks.length} songs`]
    .filter(Boolean)
    .join(" · ");

  return (
    <CollectionView
      title={album.name}
      subtitle={subtitle}
      artwork={album.artwork}
      tracks={albumTracks}
    />
  );
}
