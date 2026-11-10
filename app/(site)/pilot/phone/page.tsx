import Link from "next/link";
import { Contact, Email, Guide, guideMetadata, Links, Questions, Tip, UI, type GuidePart } from "../_guide/parts";
import { playTesting, qrFor, testFlight, testFlightApp } from "../links";

export const metadata = guideMetadata(
  "Set up Porch on your phone | HelloPorch",
  "Get Porch on your iPhone or Android phone, join your family’s Porch and let calls ring.",
);

// The family phone guide: what everyone does on their own phone, iPhone or Android. The bedside guides cover the
// loved one's iPad or tablet, and send people here for the phone side.
const parts: GuidePart[] = [
  {
    id: "get",
    title: "Get Porch",
    body: (
      <>
        <p>
          Someone in your family has set up Porch for your loved one and invited you. During the pilot, Porch is a
          test app. Follow the steps for your phone, then open your invitation.
        </p>
        <h3>On an iPhone</h3>
        <Links
          items={[
            {
              name: "TestFlight on the App Store",
              href: testFlightApp,
              qr: qrFor(testFlightApp),
              device: "your iPhone",
              how: (
                <>
                  Install this first. Tap <UI>Get</UI> to install Apple’s free TestFlight app. You don’t need to open it.
                </>
              ),
            },
            {
              name: "Porch on TestFlight",
              href: testFlight,
              qr: qrFor(testFlight),
              sent: "I’ll send you this link.",
              device: "your iPhone",
              how: (
                <>
                  Once TestFlight is installed, open this link and tap <UI>Accept</UI>, then <UI>Install</UI>.
                </>
              ),
            },
          ]}
        />
        <h3>On an Android phone</h3>
        <Links
          items={[
            {
              name: "Email me your Google account",
              how: (
                <>
                  Do this first. Email me at <Email /> the address of the Google account you use in Google Play.
                  It’s usually a Gmail address, but any Google account works. The next link works once I’ve added it.
                </>
              ),
            },
            {
              name: "Porch on Google Play",
              href: playTesting,
              qr: qrFor(playTesting),
              sent: "I’ll send you this link.",
              device: "your Android phone",
              how: (
                <>
                  Once I’ve added your Google account, open this link, accept the invitation and tap <UI>Install</UI>.
                </>
              ),
            },
          ]}
        />
        <h3>Then, on either phone</h3>
        <Links
          items={[
            {
              name: "Your invitation",
              sent: "From whoever invited you, or the code on your loved one’s iPad or tablet.",
              device: "your own phone",
              how: "It works once and expires after 24 hours.",
            },
          ]}
        />
        <Tip>
          <p>
            If you get stuck at any point, <Contact />.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "join",
    title: "Join your family",
    body: (
      <ol>
        <li>
          Open your invitation on your phone. Tap the link in your text or email, or point your phone’s Camera at the
          code on your loved one’s iPad or tablet and tap the link that appears.
        </li>
        <li>
          Porch opens. Tap <UI>Join family</UI>.
        </li>
        <li>
          If the link opens a web page instead, tap <UI>Open invitation in Porch</UI>.
        </li>
      </ol>
    ),
  },
  {
    id: "ring",
    title: "Let calls ring your phone",
    body: (
      <>
        <h3>On an iPhone</h3>
        <p>
          When Porch asks, allow notifications and the microphone. A Focus, Do Not Disturb or the Ring/Silent switch
          can silence Porch calls.
        </p>
        <h3>On an Android phone</h3>
        <p>
          Look at the top of Porch. Under <UI>Ring when Porch is closed</UI>, tap <UI>Allow</UI> and allow what it
          asks. Under <UI>Show calls on the lock screen</UI>, tap <UI>Open settings</UI> and allow full-screen
          notifications.
        </p>
      </>
    ),
  },
  {
    id: "help",
    title: "If something isn’t working",
    body: (
      <Questions
        items={[
          {
            q: "My phone doesn’t ring when my loved one calls.",
            a: (
              <>
                <p>
                  On an iPhone, check that Porch’s notifications and microphone are allowed in Settings, under Porch. A
                  Focus, Do Not Disturb or the Ring/Silent switch can silence Porch calls.
                </p>
                <p>
                  On Android, open Porch and follow any card at the top, such as <UI>Ring when Porch is closed</UI>.
                  Check that Porch’s notifications are on and Do Not Disturb is off.
                </p>
              </>
            ),
          },
          {
            q: "My phone won’t join from the invitation.",
            a: (
              <p>
                If the link opens a web page, tap <UI>Open invitation in Porch</UI>. Or tap <UI>Copy invitation</UI>,
                open Porch, tap <UI>I’m joining my family</UI>, paste it into <UI>Porch invitation</UI> on an iPhone or{" "}
                <UI>Invitation link</UI> on Android, and tap <UI>Join family</UI>.
              </p>
            ),
          },
          {
            q: "My invitation stopped working.",
            a: <p>Invitations work once and expire after 24 hours. Ask whoever invited you for a new one.</p>,
          },
          {
            q: "Google Play says Porch isn’t available.",
            a: (
              <p>
                In Google Play, tap your profile picture and check the email address. If it’s different from the one
                you sent me, switch accounts or send me that address.
              </p>
            ),
          },
          {
            q: "Porch won’t open on my iPhone, or says it has expired.",
            a: (
              <p>
                Each test version lasts 90 days. Open TestFlight and tap <UI>Update</UI> next to Porch, and turn on{" "}
                <UI>Automatic Updates</UI> so it stays current.
              </p>
            ),
          },
          {
            q: "My phone says Porch isn’t ready.",
            a: (
              <p>
                Your loved one’s iPad or tablet is off, unplugged or offline, or Porch isn’t open on it. Ask whoever
                looks after it to check.
              </p>
            ),
          },
          {
            q: "How do I get help?",
            a: (
              <p>
                Tell me what happened and which phone you were using. You can <Contact />. If there’s an error on the
                screen, a photo helps.
              </p>
            ),
          },
        ]}
      />
    ),
  },
];

export default function PhoneGuide() {
  return (
    <Guide
      eyebrow="Porch pilot guide"
      title={
        <>
          Set up Porch on your <em>phone</em>
        </>
      }
      lede={
        <p>
          For family and friends invited to a loved one’s Porch, on an iPhone or an Android phone: get Porch, join
          and make sure calls ring.
        </p>
      }
      aside={
        <>
          Setting up your loved one’s Porch? Start with the <Link href="/pilot/ios">iPad guide</Link> or the{" "}
          <Link href="/pilot/android">Android tablet guide</Link>.
        </>
      }
      parts={parts}
    />
  );
}
