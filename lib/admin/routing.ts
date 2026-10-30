/** The admin page answers only on its own host, and only on a deployment with `PORCH_ADMIN_ENABLED=1`: the calling
 * project. The website project serves the same code, so there it answers 404. */
export const adminHost = "admin.helloporch.store";
export const adminEnabled = () => process.env.PORCH_ADMIN_ENABLED === "1";

/** In development, `admin.localhost` on any port stands in for the admin host. */
export function isAdminHost(host: string | null | undefined, development = process.env.NODE_ENV === "development") {
  const value = host?.toLowerCase() ?? "";
  return value === adminHost || (development && /^admin\.localhost(:\d+)?$/.test(value));
}

/** Where Proxy sends a request: the admin host's paths go to the `/admin` routes and nowhere else, and `/admin` answers
 * 404 on every other host. `undefined` leaves the request alone. */
export function adminRoute(host: string | null | undefined, pathname: string, enabled = adminEnabled(), development?: boolean): { rewrite: string } | { notFound: true } | undefined {
  if (isAdminHost(host, development)) return enabled ? { rewrite: pathname === "/" ? "/admin" : `/admin${pathname}` } : { notFound: true };
  if (pathname === "/admin" || pathname.startsWith("/admin/")) return { notFound: true };
  return undefined;
}

/** No third-party scripts or frames, and nothing kept or indexed. Scripts need this response's nonce, which Next.js adds
 * to its own. Development needs `eval` for React's error overlay and plain http. */
export function adminHeaders(nonce: string, development = process.env.NODE_ENV === "development"): Record<string, string> {
  const policy = [
    "default-src 'self'", `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${development ? " 'unsafe-eval'" : ""}`,
    // A nonce turns off 'unsafe-inline', which development's style updates need.
    development ? "style-src 'self' 'unsafe-inline'" : `style-src 'self' 'nonce-${nonce}'`, "img-src 'self' data: blob:", "font-src 'self'", "connect-src 'self'",
    "object-src 'none'", "base-uri 'none'", "form-action 'self'", "frame-ancestors 'none'", ...(development ? [] : ["upgrade-insecure-requests"]),
  ].join("; ");
  return { "Content-Security-Policy": policy, "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow", "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY" };
}
