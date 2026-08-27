// Aurora Music audio engine.
// A single shared HTMLAudioElement routed through a Web Audio graph so we can
// apply a 10-band equalizer. Also wires the Media Session API for lock-screen
// / notification / Bluetooth controls. Client-only singleton.

import { EQ_FREQUENCIES } from "../types";
import { Capacitor } from "@capacitor/core";
import { MediaSession as NativeMediaSession } from "@capgo/capacitor-media-session";

export interface EngineCallbacks {
  onTime?: (t: number) => void;
  onDuration?: (d: number) => void;
  onEnded?: () => void;
  onPlay?: () => void;
  onPause?: () => void;
  onError?: () => void;
}

class AudioEngine {
  private audio: HTMLAudioElement | null = null;
  private ctx: AudioContext | null = null;
  private source: MediaElementAudioSourceNode | null = null;
  private filters: BiquadFilterNode[] = [];
  private preamp: GainNode | null = null;
  private cb: EngineCallbacks = {};
  private graphReady = false;

  init() {
    if (this.audio || typeof window === "undefined") return;
    const audio = new Audio();
    audio.preload = "metadata";
    audio.crossOrigin = "anonymous";
    this.audio = audio;

    audio.addEventListener("timeupdate", () => this.cb.onTime?.(audio.currentTime));
    audio.addEventListener("durationchange", () => {
      if (Number.isFinite(audio.duration)) this.cb.onDuration?.(audio.duration);
    });
    audio.addEventListener("ended", () => this.cb.onEnded?.());
    audio.addEventListener("play", () => this.cb.onPlay?.());
    audio.addEventListener("pause", () => this.cb.onPause?.());
    audio.addEventListener("error", () => this.cb.onError?.());
  }

  setCallbacks(cb: EngineCallbacks) {
    this.cb = cb;
  }

  private buildGraph() {
    if (this.graphReady || !this.audio) return;
    try {
      const browserWindow = window as typeof window & {
        webkitAudioContext?: typeof AudioContext;
      };
      const Ctx = window.AudioContext || browserWindow.webkitAudioContext;
      if (!Ctx) return;
      this.ctx = new Ctx();
      this.source = this.ctx.createMediaElementSource(this.audio);
      this.preamp = this.ctx.createGain();
      this.filters = EQ_FREQUENCIES.map((freq) => {
        const f = this.ctx!.createBiquadFilter();
        f.type = "peaking";
        f.frequency.value = freq;
        f.Q.value = 1.1;
        f.gain.value = 0;
        return f;
      });
      // source -> preamp -> f0 -> f1 -> ... -> destination
      let node: AudioNode = this.source;
      node.connect(this.preamp);
      node = this.preamp;
      for (const f of this.filters) {
        node.connect(f);
        node = f;
      }
      node.connect(this.ctx.destination);
      this.graphReady = true;
    } catch {
      // Web Audio unavailable — fall back to plain element playback.
      this.graphReady = false;
    }
  }

  async load(src: string, autoplay: boolean): Promise<boolean> {
    this.init();
    if (!this.audio) return false;
    this.audio.src = src;
    this.audio.load();
    return autoplay ? this.play() : true;
  }

  async play(): Promise<boolean> {
    this.init();
    if (!this.audio) return false;
    this.buildGraph();
    if (this.ctx && this.ctx.state === "suspended") {
      try {
        await this.ctx.resume();
      } catch {
        /* ignore */
      }
    }
    try {
      await this.audio.play();
      return true;
    } catch {
      return false;
    }
  }

  pause() {
    this.audio?.pause();
  }

  seek(t: number) {
    if (this.audio) this.audio.currentTime = t;
  }

  setVolume(v: number) {
    if (this.audio) this.audio.volume = Math.max(0, Math.min(1, v));
  }

  setRate(r: number) {
    if (this.audio) this.audio.playbackRate = r;
  }

  setEqEnabled(enabled: boolean, bands: number[]) {
    this.buildGraph();
    this.applyBands(enabled ? bands : new Array(EQ_FREQUENCIES.length).fill(0));
  }

  setBands(bands: number[]) {
    this.applyBands(bands);
  }

  private applyBands(bands: number[]) {
    this.filters.forEach((f, i) => {
      if (bands[i] !== undefined) f.gain.value = bands[i];
    });
  }

  get currentTime() {
    return this.audio?.currentTime ?? 0;
  }

  get element() {
    return this.audio;
  }
}

export const engine = new AudioEngine();

// ---- Media Session helpers ----

export function setMediaSessionMeta(opts: {
  title: string;
  artist: string;
  album: string;
  artwork: string | null;
}) {
  const artwork = opts.artwork ? [{ src: opts.artwork, sizes: "512x512", type: "image/png" }] : [];
  if (Capacitor.isNativePlatform()) {
    void NativeMediaSession.setMetadata({
      title: opts.title,
      artist: opts.artist,
      album: opts.album,
      artwork,
    }).catch(() => undefined);
    return;
  }
  if (typeof navigator === "undefined" || !("mediaSession" in navigator)) return;
  navigator.mediaSession.metadata = new MediaMetadata({
    title: opts.title,
    artist: opts.artist,
    album: opts.album,
    artwork,
  });
}

export function setMediaSessionHandlers(handlers: {
  play: () => void;
  pause: () => void;
  next: () => void;
  prev: () => void;
  seek: (t: number) => void;
}) {
  if (Capacitor.isNativePlatform()) {
    const actions = [
      ["play", handlers.play],
      ["pause", handlers.pause],
      ["nexttrack", handlers.next],
      ["previoustrack", handlers.prev],
    ] as const;
    for (const [action, handler] of actions) {
      void NativeMediaSession.setActionHandler({ action }, handler).catch(() => undefined);
    }
    void NativeMediaSession.setActionHandler({ action: "seekto" }, (details) => {
      if (details.seekTime != null) handlers.seek(details.seekTime);
    }).catch(() => undefined);
    return;
  }
  if (typeof navigator === "undefined" || !("mediaSession" in navigator)) return;
  const ms = navigator.mediaSession;
  ms.setActionHandler("play", () => handlers.play());
  ms.setActionHandler("pause", () => handlers.pause());
  ms.setActionHandler("nexttrack", () => handlers.next());
  ms.setActionHandler("previoustrack", () => handlers.prev());
  try {
    ms.setActionHandler("seekto", (d) => {
      if (d.seekTime != null) handlers.seek(d.seekTime);
    });
  } catch {
    /* not supported */
  }
}

export function setMediaSessionPlaybackState(state: "playing" | "paused" | "none") {
  if (Capacitor.isNativePlatform()) {
    void NativeMediaSession.setPlaybackState({ playbackState: state }).catch(() => undefined);
    return;
  }
  if (typeof navigator === "undefined" || !("mediaSession" in navigator)) return;
  navigator.mediaSession.playbackState = state;
}

export function setMediaSessionPositionState(opts: {
  duration: number;
  position: number;
  playbackRate: number;
}) {
  if (!Number.isFinite(opts.duration) || opts.duration <= 0) return;
  const position = Math.max(0, Math.min(opts.position, opts.duration));
  if (Capacitor.isNativePlatform()) {
    void NativeMediaSession.setPositionState({ ...opts, position }).catch(() => undefined);
    return;
  }
  if (typeof navigator === "undefined" || !("mediaSession" in navigator)) return;
  try {
    navigator.mediaSession.setPositionState({ ...opts, position });
  } catch {
    /* optional browser feature */
  }
}
