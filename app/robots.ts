import type { MetadataRoute } from "next";
import { SITE_URL } from "../lib/site-metadata.ts";

// Crawlers may read every page. The private pages say noindex themselves, which only works if crawlers can see them,
// so only the API is off limits. Preview deployments get Vercel's own noindex header.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: "/api/" },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
