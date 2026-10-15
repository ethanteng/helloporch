import DemoVideo from "@/components/DemoVideo";
import PorchFace from "@/components/PorchFace";
import PorchKeypad, { ScreenKey } from "@/components/PorchKeypad";
import { HeroWaitlist, JoinWaitlist, WaitlistProvider } from "@/components/Waitlist";

const PHONE_STEPS = ["Unlock the phone", "Find the video app", "Scroll to Sarah", "Tap the tiny camera icon"];

export default function Home() {
  return (
    <WaitlistProvider>
      <div className="page">
        <nav className="nav">
          <a href="#" className="logo" aria-label="Porch home">
            porch<span>.</span>
          </a>
          <a href="#join" className="nav__cta">
            Join the waitlist
          </a>
        </nav>

        <header className="hero">
          <div className="hero__badge">Video calls for individuals who can&rsquo;t use a phone anymore</div>
          <h1 className="hero__title">
            <span className="hero__title-lead">Phones can get complicated.</span>
            <em>Seeing family shouldn&rsquo;t.</em>
          </h1>
          <p className="hero__lede">
            Porch is a tablet and a large-button keypad for individuals with dementia or limited dexterity. Each button is
            someone they love. <strong>One press starts a video call.</strong>
          </p>
          <HeroWaitlist />
        </header>

        <section className="device" aria-label="The Porch tablet and keypad">
          <div className="device__stage">
            <div className="device__tablet-wrap">
              <div className="device__tablet">
                <div className="device__screen">
                  <PorchFace who="sarah" shape="rect" width="100%" height="100%" talking style={{ position: "absolute", inset: 0 }} />
                  <div className="device__name">Sarah</div>
                  <div className="device__self">
                    <PorchFace who="walt" shape="rect" width="100%" height="100%" style={{ position: "absolute", inset: 0 }} />
                  </div>
                </div>
              </div>
              <div className="device__stand" />
            </div>
            <PorchKeypad />
          </div>
        </section>

        <section className="compare">
          <div className="compare__group">
            <h2 className="section-title section-title--sm">Four steps on a phone.</h2>
            <ul className="compare__steps">
              {PHONE_STEPS.map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ul>
          </div>
          <div className="compare__group">
            <h2 className="section-title section-title--lg">
              <em className="bold-italic">One on Porch.</em>
            </h2>
            <div className="call-pill">
              <div className="call-pill__ring" />
              <div className="call-pill__ring call-pill__ring--late" />
              <div className="call-pill__face">
                <PorchFace who="sarah" size={104} talking />
              </div>
              Call Sarah
            </div>
          </div>
        </section>

        <section className="steps">
          <div className="steps__grid">
            <article className="step">
              <div className="step__art" style={{ background: "oklch(0.93 0.03 75)" }}>
                <TableScene />
              </div>
              <StepText n={1} title="You set it on the table.">
                A tablet on a sturdy stand, with a large-button keypad beside it. Plug it in once and add the people they
                call most.
              </StepText>
            </article>
            <article className="step">
              <div className="step__art step__art--center" style={{ background: "oklch(0.88 0.075 80)" }}>
                <div className="press-face">
                  <PorchFace who="sarah" size={164} />
                  <div className="press-face__tap" />
                </div>
              </div>
              <StepText n={2} title="They press a face.">
                Each button has a photo and a name in large print. One press starts a video call.
              </StepText>
            </article>
            <article className="step">
              <div className="step__art step__art--center" style={{ background: "oklch(0.87 0.05 45)" }}>
                <div className="phone">
                  <div className="phone__screen">
                    <PorchFace who="walt" shape="rect" width="100%" height="100%" talking style={{ position: "absolute", inset: 0 }} />
                    <div className="phone__caption">Dad · Porch</div>
                  </div>
                </div>
              </div>
              <StepText n={3} title="You answer on your phone.">
                The call rings in the Porch app, like any other video call.
              </StepText>
            </article>
          </div>
        </section>

        <section className="features">
          <div className="features__grid">
            <article className="feature">
              <div className="feature__art">
                <div className="incoming">
                  <div className="incoming__screen">
                    <div className="incoming__face">
                      <PorchFace who="mike" size={58} />
                    </div>
                    <div className="incoming__title">Mike is calling</div>
                    <div className="incoming__pill">Answering automatically</div>
                  </div>
                </div>
              </div>
              <h3 className="feature__title">Call in anytime.</h3>
              <p className="feature__body">Porch picks up for them, so they don&rsquo;t have to touch anything to see you.</p>
            </article>
            <article className="feature">
              <div className="feature__art">
                <div className="big-help">HELP</div>
              </div>
              <h3 className="feature__title">One red button for emergencies.</h3>
              <p className="feature__body">It calls everyone on their list until someone picks up.</p>
            </article>
            <article className="feature">
              <div className="feature__art">
                <KeysCloseUp />
              </div>
              <h3 className="feature__title">Made for unsteady hands.</h3>
              <p className="feature__body">Buttons are large, firm, and forgiving. A light tap and a heavy press both work.</p>
            </article>
          </div>
        </section>

        <section id="join" className="join">
          <div className="join__copy">
            <h2 className="join__title">
              Get Porch <em>first.</em>
            </h2>
            <p className="join__body">
              We&rsquo;re building early units now. Join the waitlist and we&rsquo;ll email you when one can be yours.
            </p>
            <JoinWaitlist />
          </div>
          <div className="film">
            <DemoVideo />
          </div>
        </section>

        <footer className="footer">
          <div>© 2026 Porch</div>
          <div>Made for families, by a family.</div>
        </footer>
      </div>
    </WaitlistProvider>
  );
}

function StepText({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <div className="step__text">
      <div className="step__num">{n}</div>
      <div className="step__copy">
        <h3 className="step__title">{title}</h3>
        <p className="step__body">{children}</p>
      </div>
    </div>
  );
}

/* Step 1: tablet on a stand and the keypad, sitting on a table in perspective. */
function TableScene() {
  const abs = (s: React.CSSProperties): React.CSSProperties => ({ position: "absolute", ...s });
  return (
    <>
      <div style={abs({ left: 0, right: 0, bottom: 0, height: 22, background: "oklch(0.86 0.03 68)" })} />
      <div style={abs({ left: 44, top: 206, width: 14, height: 60, background: "oklch(0.55 0.07 52)" })} />
      <div style={abs({ right: 44, top: 206, width: 14, height: 60, background: "oklch(0.55 0.07 52)" })} />
      <div style={abs({ left: 18, right: 18, top: 146, height: 48, background: "oklch(0.74 0.07 58)", clipPath: "polygon(7% 0,93% 0,100% 100%,0 100%)" })} />
      <div style={abs({ left: 18, right: 18, top: 194, height: 14, background: "oklch(0.6 0.07 54)", borderRadius: "0 0 4px 4px" })} />
      <div style={abs({ left: "50%", top: 160, width: 150, height: 16, transform: "translateX(-50%)", borderRadius: "50%", background: "radial-gradient(closest-side,oklch(0.35 0.05 50 / .45),oklch(0.35 0.05 50 / 0))" })} />
      <div style={abs({ left: "50%", top: 184, width: 200, height: 16, transform: "translateX(-50%)", borderRadius: "50%", background: "radial-gradient(closest-side,oklch(0.35 0.05 50 / .5),oklch(0.35 0.05 50 / 0))" })} />
      <div style={abs({ left: "50%", top: 44, transform: "translateX(-50%)", display: "flex", flexDirection: "column", alignItems: "center" })}>
        <div style={{ width: 168, height: 108, padding: 6, borderRadius: 14, background: "oklch(0.24 0.02 50)", boxSizing: "border-box" }}>
          <div style={{ height: "100%", borderRadius: 8, background: "oklch(0.945 0.02 75)", display: "grid", placeItems: "center", font: "400 14px var(--font-serif), serif", color: "oklch(0.25 0.03 45)" }}>
            Good afternoon, Walt
          </div>
        </div>
        <div style={{ width: 56, height: 22, background: "oklch(0.6 0.06 60)", clipPath: "polygon(22% 0,78% 0,100% 100%,0 100%)" }} />
      </div>
      <PorchKeypad style={{ position: "absolute", left: "calc(50% - 78px)", top: 120, transform: "scale(0.27)", transformOrigin: "0 0" }} />
    </>
  );
}

/* "Made for unsteady hands": the Sarah key pressed under a fingertip, the Mike key raised. */
function KeysCloseUp() {
  const abs = (s: React.CSSProperties): React.CSSProperties => ({ position: "absolute", transformStyle: "preserve-3d", ...s });
  return (
    <div style={{ position: "relative", width: 280, height: 200, perspective: 900 }}>
      <div
        style={abs({
          left: 10,
          top: 24,
          width: 260,
          height: 160,
          borderRadius: 28,
          background: "linear-gradient(165deg,oklch(0.995 0.003 85),oklch(0.93 0.006 80))",
          boxShadow: "inset 0 2px 0 #fff,0 10px 0 oklch(0.84 0.008 75),0 24px 30px -14px oklch(0.3 0.05 50 / .45)",
          transform: "rotateX(30deg) rotateY(-12deg)",
        })}
      >
        <div style={abs({ left: 24, top: 30 })}>
          <ScreenKey who="sarah" name="Sarah" pressed />
        </div>
        <div style={abs({ left: 136, top: 30 })}>
          <ScreenKey who="mike" name="Mike" />
        </div>
        <div style={abs({ left: 26, top: 32, width: 96, height: 96, borderRadius: "50%", border: "3px solid oklch(0.52 0.13 40 / .5)", boxSizing: "border-box", transform: "translateZ(34px)" })} />
        <div style={abs({ left: 40, top: 46, width: 68, height: 68, borderRadius: "50%", background: "oklch(0.82 0.06 55 / .6)", border: "2px solid oklch(0.97 0.02 60 / .9)", boxSizing: "border-box", transform: "translateZ(36px)" })} />
      </div>
    </div>
  );
}
