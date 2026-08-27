import { useRef, useState, type ReactNode } from "react";
import { FolderOpen, FileMusic, Link2, Loader2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { importFiles, type ImportProgress } from "@/lib/import";
import { trackFromUrl } from "@/lib/metadata";
import { usePlayer } from "@/store/player";
import { toast } from "sonner";

export function AddMusicDialog({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const [progress, setProgress] = useState<ImportProgress | null>(null);
  const [url, setUrl] = useState("");
  const [urlTitle, setUrlTitle] = useState("");
  const [downloadAllowed, setDownloadAllowed] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const folderRef = useRef<HTMLInputElement>(null);
  const addTracks = usePlayer((s) => s.addTracks);

  async function handleFiles(list: FileList | null) {
    if (!list || list.length === 0) return;
    setProgress({ done: 0, total: list.length });
    const tracks = await importFiles(Array.from(list), setProgress);
    setProgress(null);
    if (tracks.length === 0) {
      toast.error("No supported audio files found");
      return;
    }
    addTracks(tracks);
    toast.success(`Added ${tracks.length} song${tracks.length === 1 ? "" : "s"}`);
    setOpen(false);
  }

  function handleAddUrl() {
    if (!url.trim()) return;
    try {
      new URL(url);
    } catch {
      toast.error("Enter a valid URL");
      return;
    }
    addTracks([trackFromUrl(url.trim(), urlTitle, downloadAllowed)]);
    toast.success("Stream added");
    setUrl("");
    setUrlTitle("");
    setDownloadAllowed(false);
    setOpen(false);
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>{children}</DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="font-display">Add music</DialogTitle>
          <DialogDescription>
            Import audio from your device or stream from a direct link.
          </DialogDescription>
        </DialogHeader>

        <Tabs defaultValue="local">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="local">Local files</TabsTrigger>
            <TabsTrigger value="url">From URL</TabsTrigger>
          </TabsList>

          <TabsContent value="local" className="space-y-3 pt-2">
            {progress ? (
              <div className="flex flex-col items-center gap-3 py-8">
                <Loader2 className="h-7 w-7 animate-spin text-primary" />
                <p className="text-sm text-muted-foreground">
                  Scanning {progress.done} / {progress.total}
                </p>
              </div>
            ) : (
              <>
                <button
                  onClick={() => folderRef.current?.click()}
                  className="flex w-full items-center gap-3 rounded-xl border border-border bg-card p-4 text-left transition-colors hover:bg-accent"
                >
                  <FolderOpen className="h-6 w-6 text-primary" />
                  <div>
                    <p className="text-sm font-medium">Pick a folder</p>
                    <p className="text-xs text-muted-foreground">Scan an entire music folder</p>
                  </div>
                </button>
                <button
                  onClick={() => fileRef.current?.click()}
                  className="flex w-full items-center gap-3 rounded-xl border border-border bg-card p-4 text-left transition-colors hover:bg-accent"
                >
                  <FileMusic className="h-6 w-6 text-primary" />
                  <div>
                    <p className="text-sm font-medium">Choose files</p>
                    <p className="text-xs text-muted-foreground">MP3, FLAC, AAC, M4A, OGG, WAV…</p>
                  </div>
                </button>
                <p className="text-center text-xs text-muted-foreground">
                  Files stay on your device — nothing is uploaded.
                </p>
              </>
            )}
            <input
              ref={folderRef}
              type="file"
              // @ts-expect-error non-standard but widely supported
              webkitdirectory=""
              directory=""
              multiple
              hidden
              onChange={(e) => handleFiles(e.target.files)}
            />
            <input
              ref={fileRef}
              type="file"
              accept="audio/*,.mp3,.flac,.aac,.m4a,.ogg,.wav,.opus"
              multiple
              hidden
              onChange={(e) => handleFiles(e.target.files)}
            />
          </TabsContent>

          <TabsContent value="url" className="space-y-3 pt-2">
            <Input
              placeholder="https://example.com/song.mp3"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
            />
            <Input
              placeholder="Title (optional)"
              value={urlTitle}
              onChange={(e) => setUrlTitle(e.target.value)}
            />
            <div className="flex items-start gap-2 rounded-xl border border-border bg-secondary/40 p-3">
              <Checkbox
                id="download-permission"
                checked={downloadAllowed}
                onCheckedChange={(value) => setDownloadAllowed(value === true)}
                className="mt-0.5"
              />
              <Label htmlFor="download-permission" className="text-xs leading-relaxed">
                I have permission to download this direct audio file. Allow manual download and
                smart offline caching.
              </Label>
            </div>
            <Button onClick={handleAddUrl} className="w-full" disabled={!url.trim()}>
              <Link2 className="mr-2 h-4 w-4" /> Add stream
            </Button>
            <p className="text-xs text-muted-foreground">
              Paste a direct link to an audio file. YouTube and streaming-service pages belong in
              Online Search and are never downloaded.
            </p>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}
