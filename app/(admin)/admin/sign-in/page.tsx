import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { adminRequest, currentAdmin } from "../../../../lib/admin/request.ts";
import SignInForm from "../_ui/SignInForm";

export const metadata: Metadata = { title: "Sign in" };

export default async function SignInPage() {
  const { settings } = await adminRequest();
  if (await currentAdmin()) redirect("/");
  return (
    <main className="sign-in">
      <h1>Porch admin</h1>
      {settings ? <SignInForm /> : (
        <p className="error">The admin password isn&apos;t set up. Run <code>node scripts/admin-password.mjs</code> and save its result as <code>PORCH_ADMIN_PASSWORD_HASH</code> in this Vercel project, then redeploy.</p>
      )}
    </main>
  );
}
