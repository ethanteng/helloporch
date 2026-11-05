import Link from "next/link";
import PorchLogo from "@/components/PorchLogo";

// While the Porch keypad is being designed, the pilot is the main ask: the button joins the pilot, and the waitlist is a
// plain link. Pages without their own waitlist section send that link to the home page's.
export default function SiteNav({ current, joinHref = "#join" }: { current?: "pilot" | "features" | "story"; joinHref?: string }) {
  return (
    <nav className="nav" aria-label="Main navigation">
      <Link href="/" className="logo" aria-label="HelloPorch home">
        <PorchLogo />
      </Link>
      <div className="nav__actions">
        <div className="nav__links">
          <Link href="/features" className="nav__link nav__link--featured" aria-current={current === "features" ? "page" : undefined}>
            See how it works
          </Link>
          <Link href="/story" className="nav__link" aria-current={current === "story" ? "page" : undefined}>
            Our story
          </Link>
          <a href={joinHref} className="nav__link">
            Waitlist
          </a>
        </div>
        <Link href="/pilot" className="nav__cta" aria-current={current === "pilot" ? "page" : undefined}>
          Join the pilot
        </Link>
      </div>
    </nav>
  );
}
