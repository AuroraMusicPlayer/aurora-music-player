import { useEffect, type ReactNode } from "react";
import { AnimatePresence } from "framer-motion";
import { BottomNav } from "./BottomNav";
import { MiniPlayer } from "./MiniPlayer";
import { FullPlayer } from "./FullPlayer";
import { Toaster } from "@/components/ui/sonner";
import { usePlayer } from "@/store/player";
import { useSettings } from "@/store/settings";
import { useOnline } from "@/store/online";
import { OnlinePlayerDock } from "./OnlinePlayerDock";

export function AppShell({ children }: { children: ReactNode }) {
  const hydrate = usePlayer((s) => s.hydrate);
  const currentId = usePlayer((s) => s.currentId);
  const playerOpen = usePlayer((s) => s.playerOpen);
  const hydrateSettings = useSettings((s) => s.hydrate);
  const hydrateOnline = useOnline((s) => s.hydrate);

  useEffect(() => {
    hydrateSettings();
    hydrateOnline();
    void hydrate();
  }, [hydrate, hydrateOnline, hydrateSettings]);

  return (
    <div className="relative mx-auto flex h-[100dvh] max-w-3xl flex-col overflow-hidden">
      {/* Scrollable content */}
      <main className="flex-1 overflow-y-auto pb-2">{children}</main>

      {/* Mini player */}
      <AnimatePresence>{currentId && <MiniPlayer key="mini" />}</AnimatePresence>

      {/* Visible, route-independent hosted player. */}
      <OnlinePlayerDock />

      {/* Bottom nav */}
      <BottomNav />

      {/* Full-screen player overlay */}
      <AnimatePresence>{playerOpen && currentId && <FullPlayer key="full" />}</AnimatePresence>

      <Toaster position="top-center" />
    </div>
  );
}
