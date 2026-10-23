import Link from "next/link";
import SocialLinks from "@/components/SocialLinks";

export default function SiteFooter() {
  return (
    <footer className="footer">
      <div className="footer__copy">
        <div>© 2026 Porch</div>
        <div>Made for families, by a family.</div>
        <Link href="/privacy" className="footer__link">
          Privacy policy
        </Link>
      </div>
      <SocialLinks />
    </footer>
  );
}
