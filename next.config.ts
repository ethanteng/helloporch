import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // This machine's LAN address, so a phone or another device on the
  // network can load the dev server's hot-reload resources.
  allowedDevOrigins: ["192.168.4.27"],
};

export default nextConfig;
