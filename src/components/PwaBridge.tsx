import { useEffect, useState } from "react";

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

/**
 * PWA glue: service worker registration, install affordance, offline notice and
 * update prompt.
 *
 * Kept in one component so the shell itself stays a layout concern. Everything
 * degrades silently where the APIs do not exist (Safari, Firefox, dev builds).
 */
export function PwaBridge() {
  const [offline, setOffline] = useState(false);
  const [installEvent, setInstallEvent] = useState<InstallPromptEvent | null>(null);
  const [installDismissed, setInstallDismissed] = useState(false);
  const [updateReady, setUpdateReady] = useState(false);

  useEffect(() => {
    setOffline(typeof navigator !== "undefined" ? !navigator.onLine : false);
  }, []);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const onOnline = () => setOffline(false);
    const onOffline = () => setOffline(true);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);

    const onBeforeInstall = (event: Event) => {
      // Chrome shows its own mini-infobar otherwise; we want our own button.
      event.preventDefault();
      setInstallEvent(event as InstallPromptEvent);
    };
    window.addEventListener("beforeinstallprompt", onBeforeInstall);

    // Ask the browser not to evict this origin's IndexedDB, which holds the
    // user's audio. Best effort: browsers may downgrade it silently.
    void navigator.storage?.persist?.();

    const hadController = Boolean(navigator.serviceWorker?.controller);

    // Never register in dev: a cached shell fights every hot reload.
    if (import.meta.env.PROD && "serviceWorker" in navigator) {
      navigator.serviceWorker
        .register("/sw.js")
        .then((registration) => {
          registration.addEventListener("updatefound", () => {
            const installing = registration.installing;
            if (!installing) return;
            installing.addEventListener("statechange", () => {
              // A worker installed while one already controls the page means an
              // update is waiting, not a first install.
              if (installing.state === "installed" && hadController) {
                setUpdateReady(true);
              }
            });
          });
        })
        .catch((error) => console.warn("Service worker registration failed", error));

      navigator.serviceWorker.addEventListener("controllerchange", () => {
        // Only reload for genuine updates; on first install the page is fine.
        if (hadController) window.location.reload();
      });
    }

    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
      window.removeEventListener("beforeinstallprompt", onBeforeInstall);
    };
  }, []);

  const install = async () => {
    if (!installEvent) return;
    await installEvent.prompt();
    const choice = await installEvent.userChoice.catch(() => ({ outcome: "dismissed" as const }));
    if (choice.outcome === "accepted") setInstallEvent(null);
    else setInstallDismissed(true);
  };

  const showInstall = installEvent !== null && !installDismissed;

  if (!offline && !showInstall && !updateReady) return null;

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-24 z-40 flex flex-col items-center gap-2 px-4">
      {offline && (
        <div className="pointer-events-auto rounded-full bg-amber-500/15 px-4 py-1.5 text-xs text-amber-200 ring-1 ring-amber-500/30">
          Offline — saved music still plays
        </div>
      )}

      {updateReady && (
        <div className="pointer-events-auto flex items-center gap-3 rounded-full bg-white/10 px-4 py-1.5 text-xs text-white ring-1 ring-white/15 backdrop-blur">
          New version available
          <button
            onClick={() => window.location.reload()}
            className="rounded-full bg-primary px-3 py-1 text-[11px] font-medium text-primary-foreground"
          >
            Reload
          </button>
        </div>
      )}

      {showInstall && (
        <div className="pointer-events-auto flex items-center gap-3 rounded-full bg-white/10 px-4 py-1.5 text-xs text-white ring-1 ring-white/15 backdrop-blur">
          Install Aurora for offline listening
          <button
            onClick={install}
            className="rounded-full bg-primary px-3 py-1 text-[11px] font-medium text-primary-foreground"
          >
            Install
          </button>
          <button
            onClick={() => setInstallDismissed(true)}
            aria-label="Dismiss"
            className="text-white/50 hover:text-white"
          >
            ✕
          </button>
        </div>
      )}
    </div>
  );
}
