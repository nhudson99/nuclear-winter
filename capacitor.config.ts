import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.nuclearwinter.game",
  appName: "Nuclear Winter",
  webDir: "dist",
  server: {
    androidScheme: "https",
  },
};

export default config;
