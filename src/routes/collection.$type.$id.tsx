import { createFileRoute } from "@tanstack/react-router";
import { usePlayer } from "@/store/player";
import {
  byIds,
  getArtists,
  getFolders,
  getGenres,
  getYears,
  mostPlayed,
  recentlyAdded,
  recentlyPlayed,
} from "@/lib/selectors";
import { CollectionView } from "@/components/CollectionView";
import type { Track } from "@/lib/types";

export const Route = createFileRoute("/collection/$type/$id")({
  component: CollectionPage,
});

function CollectionPage() {
  const { type, id } = Route.useParams();
  const tracks = usePlayer((s) => s.tracks);
  const stats = usePlayer((s) => s.stats);
  const favorites = usePlayer((s) => s.favorites);
  const playlists = usePlayer((s) => s.playlists);
  const removeFromPlaylist = usePlayer((s) => s.removeFromPlaylist);

  let title = "";
  let subtitle = "";
  let list: Track[] = [];
  let round = false;
  let onRemoveTrack: ((tid: string) => void) | undefined;
  let artwork: string | null = null;

  switch (type) {
    case "artist": {
      const a = getArtists(tracks).find((x) => x.id === id);
      title = a?.name ?? "Artist";
      list = a ? byIds(tracks, a.trackIds) : [];
      subtitle = `${list.length} songs`;
      artwork = a?.artwork ?? null;
      round = true;
      break;
    }
    case "genre": {
      const g = getGenres(tracks).find((x) => x.id === id);
      title = g?.name ?? "Genre";
      list = g ? byIds(tracks, g.trackIds) : [];
      subtitle = `${list.length} songs`;
      artwork = g?.artwork ?? null;
      break;
    }
    case "folder": {
      const f = getFolders(tracks).find((x) => x.id === id);
      title = f?.name ?? "Folder";
      list = f ? byIds(tracks, f.trackIds) : [];
      subtitle = `${list.length} songs`;
      artwork = f?.artwork ?? null;
      break;
    }
    case "year": {
      const y = getYears(tracks).find((x) => x.id === id);
      title = y?.name ?? "Year";
      list = y ? byIds(tracks, y.trackIds) : [];
      subtitle = `${list.length} songs`;
      artwork = y?.artwork ?? null;
      break;
    }
    case "favorites": {
      title = "Favorites";
      list = byIds(tracks, favorites);
      subtitle = `${list.length} songs`;
      artwork = list[0]?.artwork ?? null;
      break;
    }
    case "most": {
      title = "Most Played";
      list = mostPlayed(tracks, stats);
      subtitle = `${list.length} songs`;
      artwork = list[0]?.artwork ?? null;
      break;
    }
    case "recent": {
      title = "Recently Played";
      list = recentlyPlayed(tracks, stats);
      subtitle = `${list.length} songs`;
      artwork = list[0]?.artwork ?? null;
      break;
    }
    case "recentlyAdded": {
      title = "Recently Added";
      list = recentlyAdded(tracks);
      subtitle = `${list.length} songs`;
      artwork = list[0]?.artwork ?? null;
      break;
    }
    case "playlist": {
      const p = playlists.find((x) => x.id === id);
      title = p?.name ?? "Playlist";
      list = p ? byIds(tracks, p.trackIds) : [];
      subtitle = `${list.length} songs`;
      artwork = list[0]?.artwork ?? null;
      if (p) onRemoveTrack = (tid) => removeFromPlaylist(p.id, tid);
      break;
    }
    default:
      title = "Collection";
  }

  return (
    <CollectionView
      title={title}
      subtitle={subtitle}
      artwork={artwork}
      tracks={list}
      round={round}
      onRemoveTrack={onRemoveTrack}
    />
  );
}
