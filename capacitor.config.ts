import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.auroraflow.app",
  appName: "Aurora Flow",
  webDir: "dist",
  server: {
    androidScheme: "https",
  },
};

export default config;
