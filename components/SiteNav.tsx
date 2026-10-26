import Link from "next/link";
import PorchLogo from "@/components/PorchLogo";

// Pages without their own waitlist section send the button to the home page's.
export default function SiteNav({ current, joinHref = "#join" }: { current?: "pilot" | "features" | "story"; joinHref?: string }) {
  return (
    <nav className="nav" aria-label="Main navigation">
      <Link href="/" className="logo" aria-label="HelloPorch home">
        <PorchLogo />
      </Link>
      <div className="nav__actions">
        <div className="nav__links">
          <Link href="/pilot" className="nav__link" aria-current={current === "pilot" ? "page" : undefined}>
            Pilot program
          </Link>
          <Link href="/features" className="nav__link nav__link--featured" aria-current={current === "features" ? "page" : undefined}>
            See Porch in action
          </Link>
          <Link href="/story" className="nav__link" aria-current={current === "story" ? "page" : undefined}>
            Our story
          </Link>
        </div>
        <a href={joinHref} className="nav__cta">
          Join the waitlist
        </a>
      </div>
    </nav>
  );
}
