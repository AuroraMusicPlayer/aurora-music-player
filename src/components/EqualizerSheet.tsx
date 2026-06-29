import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Switch } from "@/components/ui/switch";
import { Slider } from "@/components/ui/slider";
import { usePlayer } from "@/store/player";
import { EQ_FREQUENCIES, EQ_PRESETS } from "@/lib/types";
import { cn } from "@/lib/utils";

function freqLabel(f: number) {
  return f >= 1000 ? `${f / 1000}k` : `${f}`;
}

export function EqualizerSheet({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}) {
  const eq = usePlayer((s) => s.eq);
  const setEqEnabled = usePlayer((s) => s.setEqEnabled);
  const setEqBand = usePlayer((s) => s.setEqBand);
  const setEqPreset = usePlayer((s) => s.setEqPreset);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl">
        <SheetHeader className="flex flex-row items-center justify-between">
          <SheetTitle className="font-display">Equalizer</SheetTitle>
          <Switch checked={eq.enabled} onCheckedChange={setEqEnabled} />
        </SheetHeader>

        <div className="flex flex-wrap gap-2 px-4 pb-4">
          {Object.keys(EQ_PRESETS).map((preset) => (
            <button
              key={preset}
              onClick={() => setEqPreset(preset)}
              className={cn(
                "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
                eq.preset === preset
                  ? "border-transparent aurora-bg text-primary-foreground"
                  : "border-border text-muted-foreground hover:bg-accent",
              )}
            >
              {preset}
            </button>
          ))}
        </div>

        <div
          className={cn(
            "flex items-end justify-between gap-1 px-4 pb-8 transition-opacity",
            !eq.enabled && "pointer-events-none opacity-40",
          )}
        >
          {EQ_FREQUENCIES.map((f, i) => (
            <div key={f} className="flex flex-1 flex-col items-center gap-2">
              <span className="text-[10px] tabular-nums text-muted-foreground">
                {eq.bands[i] > 0 ? "+" : ""}
                {eq.bands[i]}
              </span>
              <Slider
                orientation="vertical"
                value={[eq.bands[i]]}
                min={-12}
                max={12}
                step={1}
                onValueChange={([v]) => setEqBand(i, v)}
                className="h-40"
              />
              <span className="text-[10px] text-muted-foreground">{freqLabel(f)}</span>
            </div>
          ))}
        </div>
      </SheetContent>
    </Sheet>
  );
}
