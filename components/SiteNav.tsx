import Link from "next/link";
import PorchLogo from "@/components/PorchLogo";

export default function SiteNav({ story = false }: { story?: boolean }) {
  return (
    <nav className="nav" aria-label="Main navigation">
      <Link href="/" className="logo" aria-label="HelloPorch home">
        <PorchLogo />
      </Link>
      <div className="nav__actions">
        <Link href="/story" className="nav__story" aria-current={story ? "page" : undefined}>
          Our story
        </Link>
        <a href="#join" className="nav__cta">
          Join the waitlist
        </a>
      </div>
    </nav>
  );
}
