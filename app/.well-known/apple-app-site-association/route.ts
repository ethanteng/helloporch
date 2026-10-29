import { appSiteAssociation } from "../../../lib/invite-links.ts";

// Apple's CDN fetches this from helloporch.store, without following redirects, to let invitation links open Porch.
export function GET() {
  return Response.json(appSiteAssociation(), { headers: { "Cache-Control": "public, max-age=3600" } });
}
