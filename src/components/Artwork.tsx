import { Music } from "lucide-react";
import { cn } from "@/lib/utils";

interface ArtworkProps {
  src: string | null;
  alt?: string;
  className?: string;
  rounded?: string;
}

/** Album artwork with a graceful aurora-gradient placeholder. */
export function Artwork({ src, alt = "", className, rounded = "rounded-xl" }: ArtworkProps) {
  return (
    <div
      className={cn(
        "relative overflow-hidden bg-muted shrink-0 select-none",
        rounded,
        className,
      )}
    >
      {src ? (
        <img
          src={src}
          alt={alt}
          loading="lazy"
          draggable={false}
          className="h-full w-full object-cover"
        />
      ) : (
        <div className="flex h-full w-full items-center justify-center aurora-bg/90">
          <div className="absolute inset-0 aurora-bg opacity-90" />
          <Music className="relative h-1/3 w-1/3 text-primary-foreground/80" strokeWidth={1.5} />
        </div>
      )}
    </div>
  );
}
