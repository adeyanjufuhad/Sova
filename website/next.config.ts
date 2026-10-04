import type { NextConfig } from "next";

// A fully static site (`out/`): no server code, so it can be served by any
// static host. The waitlist form posts to the Sova API instead.
const nextConfig: NextConfig = {
  output: "export",
  // Write pages as verify/index.html: static hosts serve /verify/ from a folder.
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
