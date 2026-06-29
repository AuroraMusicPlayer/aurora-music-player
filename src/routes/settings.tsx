import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { Sun, Moon, Smartphone, Sparkles, SlidersHorizontal, Trash2, Info, Zap } from "lucide-react";
import { useSettings } from "@/store/settings";
import { usePlayer } from "@/store/player";
import { ACCENT_PRESETS, type ThemeMode } from "@/lib/types";
import { EqualizerSheet } from "@/components/EqualizerSheet";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { clearAll } from "@/lib/db";
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
  const tracks = usePlayer((s) => s.tracks);
  const [eqOpen, setEqOpen] = useState(false);

  async function clearCache() {
    if (!confirm("This removes all imported songs and data from this device. Continue?")) return;
    await clearAll();
    toast.success("Library cleared");
    setTimeout(() => location.reload(), 600);
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
                theme === mode ? "aurora-bg text-primary-foreground shadow" : "glass text-muted-foreground",
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
                accentName === a.name && "ring-2 ring-offset-2 ring-offset-background ring-foreground",
              )}
              style={{ background: a.value }}
            />
          ))}
        </div>
      </Section>

      {/* Playback */}
      <Section title="Playback">
        <Row icon={SlidersHorizontal} label="Equalizer" desc="Bass, treble & presets">
          <Button variant="secondary" size="sm" className="rounded-full" onClick={() => setEqOpen(true)}>
            Open
          </Button>
        </Row>
        <Row icon={Zap} label="Animations" desc="Smooth transitions & motion">
          <Switch checked={animations} onCheckedChange={setAnimations} />
        </Row>
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
