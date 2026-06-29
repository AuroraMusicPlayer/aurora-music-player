import { Link } from "@tanstack/react-router";
import { Artwork } from "./Artwork";

interface MediaCardProps {
  to: string;
  params?: Record<string, string>;
  title: string;
  subtitle?: string;
  artwork: string | null;
  round?: boolean;
}

/** Square tappable card for albums, artists, playlists, genres, folders. */
export function MediaCard({ to, params, title, subtitle, artwork, round }: MediaCardProps) {
  return (
    <Link
      to={to}
      params={params}
      className="group flex w-36 shrink-0 flex-col gap-2 sm:w-40"
    >
      <Artwork
        src={artwork}
        className="aspect-square w-full shadow-md transition-transform group-active:scale-95"
        rounded={round ? "rounded-full" : "rounded-2xl"}
      />
      <div className="px-0.5">
        <p className="truncate text-sm font-semibold">{title}</p>
        {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
      </div>
    </Link>
  );
}
