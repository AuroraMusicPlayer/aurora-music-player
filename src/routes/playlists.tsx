import { createFileRoute, Link } from "@tanstack/react-router";
import { Plus, Clock, History, Flame, Heart, ListMusic, MoreVertical, Pencil, Trash2 } from "lucide-react";
import { usePlayer } from "@/store/player";
import { byIds } from "@/lib/selectors";
import { Artwork } from "@/components/Artwork";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { toast } from "sonner";

export const Route = createFileRoute("/playlists")({
  head: () => ({ meta: [{ title: "Playlists — Aurora Music" }] }),
  component: PlaylistsPage,
});

const AUTO = [
  { type: "recentlyAdded", name: "Recently Added", icon: Clock },
  { type: "recent", name: "Recently Played", icon: History },
  { type: "most", name: "Most Played", icon: Flame },
  { type: "favorites", name: "Favorites", icon: Heart },
] as const;

function PlaylistsPage() {
  const tracks = usePlayer((s) => s.tracks);
  const playlists = usePlayer((s) => s.playlists);
  const createPlaylist = usePlayer((s) => s.createPlaylist);
  const renamePlaylist = usePlayer((s) => s.renamePlaylist);
  const deletePlaylist = usePlayer((s) => s.deletePlaylist);

  function newPlaylist() {
    const name = prompt("Playlist name");
    if (name?.trim()) {
      createPlaylist(name.trim());
      toast.success(`Created “${name.trim()}”`);
    }
  }

  return (
    <div className="space-y-6 pb-6">
      <header className="flex items-center justify-between px-4 pt-6">
        <h1 className="text-2xl font-extrabold font-display">Playlists</h1>
        <Button onClick={newPlaylist} size="sm" className="rounded-full">
          <Plus className="mr-1 h-4 w-4" /> New
        </Button>
      </header>

      {/* Automatic playlists */}
      <section className="grid grid-cols-2 gap-3 px-4">
        {AUTO.map(({ type, name, icon: Icon }) => (
          <Link
            key={type}
            to="/collection/$type/$id"
            params={{ type, id: "all" }}
            className="glass flex items-center gap-3 rounded-2xl p-4 transition-transform active:scale-95"
          >
            <span className="flex h-11 w-11 items-center justify-center rounded-xl aurora-bg text-primary-foreground">
              <Icon className="h-5 w-5" />
            </span>
            <span className="text-sm font-semibold leading-tight">{name}</span>
          </Link>
        ))}
      </section>

      {/* User playlists */}
      <section className="space-y-1 px-2">
        <h2 className="px-2 text-lg font-bold font-display">Your playlists</h2>
        {playlists.length === 0 ? (
          <p className="px-2 py-6 text-sm text-muted-foreground">
            No playlists yet. Tap “New” to create one.
          </p>
        ) : (
          playlists.map((p) => (
            <div
              key={p.id}
              className="group flex items-center gap-3 rounded-xl px-2 py-2 hover:bg-accent/60"
            >
              <Link
                to="/collection/$type/$id"
                params={{ type: "playlist", id: p.id }}
                className="flex min-w-0 flex-1 items-center gap-3"
              >
                <Artwork
                  src={byIds(tracks, p.trackIds)[0]?.artwork ?? null}
                  className="h-12 w-12"
                  rounded="rounded-lg"
                />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{p.name}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {p.trackIds.length} song{p.trackIds.length === 1 ? "" : "s"}
                  </p>
                </div>
              </Link>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button aria-label="Playlist options" className="rounded-full p-1.5 text-muted-foreground">
                    <MoreVertical className="h-4 w-4" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-44">
                  <DropdownMenuItem
                    onClick={() => {
                      const name = prompt("Rename playlist", p.name);
                      if (name?.trim()) renamePlaylist(p.id, name.trim());
                    }}
                  >
                    <Pencil className="mr-2 h-4 w-4" /> Rename
                  </DropdownMenuItem>
                  <DropdownMenuItem
                    className="text-destructive focus:text-destructive"
                    onClick={() => {
                      deletePlaylist(p.id);
                      toast.success("Playlist deleted");
                    }}
                  >
                    <Trash2 className="mr-2 h-4 w-4" /> Delete
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          ))
        )}
      </section>

      <div className="flex items-center justify-center gap-2 px-4 pt-2 text-xs text-muted-foreground">
        <ListMusic className="h-3.5 w-3.5" /> Playlists are saved automatically on this device.
      </div>
    </div>
  );
}
