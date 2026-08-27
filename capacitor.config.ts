import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.auroraflow.app",
  appName: "Aurora Music",
  webDir: "dist",
  server: {
    androidScheme: "https",
  },
  plugins: {
    MediaSession: {
      foregroundService: "duringPlayback",
    },
  },
};

export default config;
