import type { MetadataRoute } from "next";
import { PUBLIC_PATHS, SITE_URL } from "../lib/site-metadata.ts";

// The public pages, written exactly as their canonical links are (the home page without a trailing slash).
export default function sitemap(): MetadataRoute.Sitemap {
  return PUBLIC_PATHS.map((path) => ({ url: path === "/" ? SITE_URL : `${SITE_URL}${path}` }));
}
