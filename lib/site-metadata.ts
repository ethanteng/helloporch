import type { Metadata } from "next";

// The site's own address, for canonical links, the sitemap and link previews.
export const SITE_URL = "https://helloporch.store";

// The public pages search engines should list. Pricing, the invitation pages and admin stay out (they're noindex).
export const PUBLIC_PATHS = ["/", "/features", "/pilot", "/labels", "/story", "/privacy"];

type PageMetadata = {
  path: string;
  title: string;
  description: string;
  // What a shared link shows, when it should read differently from the search result.
  shareTitle?: string;
  shareDescription?: string;
  image: { url: string; alt: string; width?: number; height?: number };
};

// A page's title and description, its canonical address, and the card a shared link shows. Next merges each segment's
// metadata shallowly, so every page passes its own complete openGraph and twitter blocks rather than inheriting parts.
export function pageMetadata({ path, title, description, shareTitle = title, shareDescription = description, image }: PageMetadata): Metadata {
  const images = [{ width: 1200, height: 630, ...image }];
  return {
    title,
    description,
    alternates: { canonical: path },
    openGraph: {
      type: "website",
      siteName: "HelloPorch",
      locale: "en_US",
      url: path,
      title: shareTitle,
      description: shareDescription,
      images,
    },
    twitter: { card: "summary_large_image", title: shareTitle, description: shareDescription, images },
  };
}
