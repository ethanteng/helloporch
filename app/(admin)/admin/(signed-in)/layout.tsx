import { requireAdmin } from "../../../../lib/admin/request.ts";
import { signOutAction } from "../actions";
import Nav from "../_ui/Nav";

export default async function SignedInLayout({ children }: { children: React.ReactNode }) {
  // Each page checks again: a layout isn't rendered again on every navigation.
  await requireAdmin();
  return (
    <div className="shell">
      <header className="top">
        <span className="brand">Porch admin</span>
        <Nav />
        <form action={signOutAction}><button type="submit" className="secondary small">Sign out</button></form>
      </header>
      <main>{children}</main>
    </div>
  );
}
