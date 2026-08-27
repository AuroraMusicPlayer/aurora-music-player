type Listener = () => void;

const localPlaybackListeners = new Set<Listener>();

/** Prevent simultaneous native/local and hosted online playback. */
export function announceLocalPlayback(): void {
  for (const listener of localPlaybackListeners) listener();
}

export function onLocalPlayback(listener: Listener): () => void {
  localPlaybackListeners.add(listener);
  return () => localPlaybackListeners.delete(listener);
}
