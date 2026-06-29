import { Link } from "@tanstack/react-router";
import { Home, Search, Library, ListMusic, Settings } from "lucide-react";
import { cn } from "@/lib/utils";

const ITEMS = [
  { to: "/", label: "Home", icon: Home },
  { to: "/search", label: "Search", icon: Search },
  { to: "/library", label: "Library", icon: Library },
  { to: "/playlists", label: "Playlists", icon: ListMusic },
  { to: "/settings", label: "Settings", icon: Settings },
] as const;

export function BottomNav() {
  return (
    <nav className="glass mx-2 mb-2 flex items-center justify-around rounded-2xl px-1 py-1.5">
      {ITEMS.map(({ to, label, icon: Icon }) => (
        <Link
          key={to}
          to={to}
          className="flex flex-1 flex-col items-center gap-0.5 rounded-xl py-1.5 text-muted-foreground transition-colors"
          activeProps={{ className: "text-primary" }}
          activeOptions={{ exact: to === "/" }}
        >
          {({ isActive }) => (
            <>
              <span
                className={cn(
                  "flex h-7 w-12 items-center justify-center rounded-full transition-colors",
                  isActive && "bg-primary/15",
                )}
              >
                <Icon className="h-5 w-5" />
              </span>
              <span className="text-[10px] font-medium">{label}</span>
            </>
          )}
        </Link>
      ))}
    </nav>
  );
}
