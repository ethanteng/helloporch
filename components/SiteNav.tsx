import Link from "next/link";
import PorchLogo from "@/components/PorchLogo";

export default function SiteNav({ current }: { current?: "features" | "story" }) {
  return (
    <nav className="nav" aria-label="Main navigation">
      <Link href="/" className="logo" aria-label="HelloPorch home">
        <PorchLogo />
      </Link>
      <div className="nav__actions">
        <div className="nav__links">
          <Link href="/features" className="nav__link" aria-current={current === "features" ? "page" : undefined}>
            See Porch in action
          </Link>
          <Link href="/story" className="nav__link" aria-current={current === "story" ? "page" : undefined}>
            Our story
          </Link>
        </div>
        <a href="#join" className="nav__cta">
          Join the waitlist
        </a>
      </div>
    </nav>
  );
}
