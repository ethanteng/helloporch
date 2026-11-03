import { assetLinks } from "../../../lib/invite-links.ts";

// Android fetches this from helloporch.store, without following redirects, to let invitation links open Porch.
export function GET() {
  return Response.json(assetLinks(), { headers: { "Cache-Control": "public, max-age=3600" } });
}
