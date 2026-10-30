import { NextResponse, type NextRequest } from "next/server";
import { adminHeaders, adminRoute } from "./lib/admin/routing.ts";

// Only the admin page goes through here (see lib/admin/routing.ts). Each admin page and action checks the host and the
// session again, since this is an optimistic gate.
export function proxy(request: NextRequest) {
  const route = adminRoute(request.headers.get("host"), request.nextUrl.pathname);
  if (!route) return NextResponse.next();
  if ("notFound" in route) return new NextResponse("Not found", { status: 404, headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow" } });
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const headers = adminHeaders(nonce);
  const forwarded = new Headers(request.headers);
  forwarded.set("x-nonce", nonce);
  forwarded.set("Content-Security-Policy", headers["Content-Security-Policy"]);
  const response = NextResponse.rewrite(new URL(route.rewrite + request.nextUrl.search, request.url), { request: { headers: forwarded } });
  for (const [name, value] of Object.entries(headers)) response.headers.set(name, value);
  return response;
}

export const config = {
  matcher: [
    // Every path on the admin host, apart from built files and icons.
    { source: "/((?!_next/static|_next/image|favicon.ico|icon.svg|apple-icon.png).*)", has: [{ type: "header", key: "host", value: "admin\\..*" }] },
    "/admin", "/admin/:path*",
  ],
};
