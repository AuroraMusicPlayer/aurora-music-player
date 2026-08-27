import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import {
  Eye,
  EyeOff,
  HardDriveDownload,
  Info,
  KeyRound,
  Moon,
  SlidersHorizontal,
  Smartphone,
  Sparkles,
  Sun,
  Trash2,
  Wifi,
  WifiOff,
  Zap,
} from "lucide-react";
import { useSettings, type SmartCacheMode } from "@/store/settings";
import { usePlayer } from "@/store/player";
import { ACCENT_PRESETS, type ThemeMode } from "@/lib/types";
import { EqualizerSheet } from "@/components/EqualizerSheet";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { clearAll } from "@/lib/db";
import { clearCacheStore } from "@/lib/smartCache";
import { cn } from "@/lib/utils";
import { toast } from "sonner";

export const Route = createFileRoute("/settings")({
  head: () => ({ meta: [{ title: "Settings — Aurora Music" }] }),
  component: SettingsPage,
});

const THEMES: { mode: ThemeMode; label: string; icon: typeof Sun }[] = [
  { mode: "light", label: "Light", icon: Sun },
  { mode: "dark", label: "Dark", icon: Moon },
  { mode: "amoled", label: "AMOLED", icon: Sparkles },
  { mode: "system", label: "System", icon: Smartphone },
];

function SettingsPage() {
  const theme = useSettings((s) => s.theme);
  const setTheme = useSettings((s) => s.setTheme);
  const accentName = useSettings((s) => s.accentName);
  const setAccent = useSettings((s) => s.setAccent);
  const animations = useSettings((s) => s.animations);
  const setAnimations = useSettings((s) => s.setAnimations);
  const youtubeApiKey = useSettings((s) => s.youtubeApiKey);
  const setYouTubeApiKey = useSettings((s) => s.setYouTubeApiKey);
  const smartCacheMode = useSettings((s) => s.smartCacheMode);
  const setSmartCacheMode = useSettings((s) => s.setSmartCacheMode);
  const cacheLimitMb = useSettings((s) => s.cacheLimitMb);
  const setCacheLimitMb = useSettings((s) => s.setCacheLimitMb);
  const tracks = usePlayer((s) => s.tracks);
  const offlineCached = usePlayer((s) => s.offlineCached);
  const offlineCacheBytes = usePlayer((s) => s.offlineCacheBytes);
  const refreshOfflineCache = usePlayer((s) => s.refreshOfflineCache);
  const [eqOpen, setEqOpen] = useState(false);
  const [showApiKey, setShowApiKey] = useState(false);

  async function clearCache() {
    if (!confirm("This removes all imported songs and data from this device. Continue?")) return;
    await clearAll();
    toast.success("Library cleared");
    setTimeout(() => location.reload(), 600);
  }

  async function clearOfflineCache() {
    await clearCacheStore();
    await refreshOfflineCache();
    toast.success("Offline cache cleared");
  }

  return (
    <div className="space-y-7 pb-6">
      <header className="px-4 pt-6">
        <h1 className="text-2xl font-extrabold font-display">Settings</h1>
      </header>

      {/* Theme */}
      <Section title="Appearance">
        <div className="grid grid-cols-4 gap-2">
          {THEMES.map(({ mode, label, icon: Icon }) => (
            <button
              key={mode}
              onClick={() => setTheme(mode)}
              className={cn(
                "flex flex-col items-center gap-1.5 rounded-2xl py-3 text-xs font-medium transition-all",
                theme === mode
                  ? "aurora-bg text-primary-foreground shadow"
                  : "glass text-muted-foreground",
              )}
            >
              <Icon className="h-5 w-5" />
              {label}
            </button>
          ))}
        </div>

        <p className="mt-4 mb-2 text-sm font-medium">Accent color</p>
        <div className="flex flex-wrap gap-3">
          {ACCENT_PRESETS.map((a) => (
            <button
              key={a.name}
              aria-label={a.name}
              onClick={() => setAccent(a.name)}
              className={cn(
                "h-9 w-9 rounded-full transition-transform active:scale-90",
                accentName === a.name &&
                  "ring-2 ring-offset-2 ring-offset-background ring-foreground",
              )}
              style={{ background: a.value }}
            />
          ))}
        </div>
      </Section>

      {/* Playback */}
      <Section title="Playback">
        <Row icon={SlidersHorizontal} label="Equalizer" desc="Bass, treble & presets">
          <Button
            variant="secondary"
            size="sm"
            className="rounded-full"
            onClick={() => setEqOpen(true)}
          >
            Open
          </Button>
        </Row>
        <Row icon={Zap} label="Animations" desc="Smooth transitions & motion">
          <Switch checked={animations} onCheckedChange={setAnimations} />
        </Row>
      </Section>

      <Section title="Online music">
        <div className="space-y-2 py-1">
          <div className="flex items-center gap-2">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
              <KeyRound className="h-4 w-4" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium">YouTube search key</p>
              <p className="text-xs text-muted-foreground">Stored only on this device</p>
            </div>
          </div>
          <div className="flex gap-2">
            <Input
              type={showApiKey ? "text" : "password"}
              value={youtubeApiKey}
              onChange={(event) => setYouTubeApiKey(event.target.value)}
              placeholder="Paste YouTube Data API key"
              autoComplete="off"
              className="rounded-xl"
            />
            <Button
              type="button"
              size="icon"
              variant="secondary"
              className="shrink-0 rounded-xl"
              onClick={() => setShowApiKey((value) => !value)}
              aria-label={showApiKey ? "Hide key" : "Show key"}
            >
              {showApiKey ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </Button>
          </div>
          <p className="text-xs leading-relaxed text-muted-foreground">
            Direct YouTube links work without a key. A free key enables search by song name and
            playlist import.{" "}
            <a
              href="https://console.cloud.google.com/apis/library/youtube.googleapis.com"
              target="_blank"
              rel="noreferrer"
              className="font-semibold text-primary"
            >
              Create a key
            </a>
          </p>
        </div>
      </Section>

      {/* Storage */}
      <Section title="Storage">
        <Row icon={Info} label="Songs in library" desc="Stored on this device">
          <span className="text-sm font-semibold tabular-nums">{tracks.length}</span>
        </Row>
        <Row icon={Trash2} label="Clear cache & library" desc="Remove all data">
          <Button variant="destructive" size="sm" className="rounded-full" onClick={clearCache}>
            Clear
          </Button>
        </Row>
      </Section>

      {/* Smart offline cache */}
      <Section title="Smart Offline Cache">
        <p className="mb-3 text-xs text-muted-foreground leading-relaxed">
          Aurora can keep permitted direct audio streams offline. YouTube videos are never
          downloaded. Least-used cached tracks are removed first when the storage limit is reached.
        </p>
        <div className="mb-3 grid grid-cols-3 gap-2">
          {(
            [
              ["off", WifiOff, "Off"],
              ["wifi", Wifi, "Wi-Fi"],
              ["always", HardDriveDownload, "Always"],
            ] as const
          ).map(([mode, Icon, label]) => (
            <button
              key={mode}
              type="button"
              onClick={() => setSmartCacheMode(mode as SmartCacheMode)}
              className={cn(
                "flex flex-col items-center gap-1 rounded-xl px-2 py-2 text-xs font-medium",
                smartCacheMode === mode
                  ? "aurora-bg text-primary-foreground"
                  : "bg-secondary text-muted-foreground",
              )}
            >
              <Icon className="h-4 w-4" />
              {label}
            </button>
          ))}
        </div>
        <label className="mb-3 flex items-center justify-between gap-3 text-sm">
          <span>
            <span className="block font-medium">Storage limit</span>
            <span className="text-xs text-muted-foreground">Cached direct audio</span>
          </span>
          <select
            value={cacheLimitMb}
            onChange={(event) => setCacheLimitMb(Number(event.target.value))}
            className="rounded-xl border border-border bg-secondary px-3 py-2 text-sm"
          >
            <option value={512}>512 MB</option>
            <option value={1024}>1 GB</option>
            <option value={3072}>3 GB</option>
            <option value={5120}>5 GB</option>
          </select>
        </label>
        <Row
          icon={WifiOff}
          label="Cached streams"
          desc={`${formatStorage(offlineCacheBytes)} used`}
        >
          <span className="text-sm font-semibold tabular-nums">{offlineCached.length}</span>
        </Row>
        {offlineCached.length > 0 && (
          <Row icon={Trash2} label="Clear offline cache" desc="Free up cached stream storage">
            <Button
              variant="secondary"
              size="sm"
              className="rounded-full"
              onClick={clearOfflineCache}
            >
              Clear
            </Button>
          </Row>
        )}
      </Section>

      <p className="px-6 text-center text-xs text-muted-foreground">
        Aurora Music · A modern offline player. Music stays on your device.
      </p>

      <EqualizerSheet open={eqOpen} onOpenChange={setEqOpen} />
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="px-4">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
        {title}
      </h2>
      <div className="glass space-y-1 rounded-2xl p-4">{children}</div>
    </section>
  );
}

function formatStorage(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function Row({
  icon: Icon,
  label,
  desc,
  children,
}: {
  icon: typeof Sun;
  label: string;
  desc?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-3 py-2">
      <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/15 text-primary">
        <Icon className="h-4 w-4" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium">{label}</p>
        {desc && <p className="text-xs text-muted-foreground">{desc}</p>}
      </div>
      {children}
    </div>
  );
}
