"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

// Paths as the browser sees them on the admin host, without the /admin the server adds.
const pages = [{ href: "/", label: "Invitations" }, { href: "/porches", label: "Porches" }, { href: "/system", label: "System" }, { href: "/activity", label: "Activity" }];

export default function Nav() {
  const pathname = usePathname().replace(/^\/admin(?=\/|$)/, "") || "/";
  return (
    <nav aria-label="Admin">
      {pages.map(page => <Link key={page.href} href={page.href} aria-current={pathname === page.href ? "page" : undefined}>{page.label}</Link>)}
    </nav>
  );
}
