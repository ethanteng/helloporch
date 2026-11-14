import Link from "next/link";
import { Contact, Email, Guide, guideMetadata, Links, Questions, Tip, UI, type GuidePart } from "../_guide/parts";
import { playTesting, qrFor, testFlight, testFlightApp } from "../links";

export const metadata = guideMetadata(
  "Set up Porch on your phone | HelloPorch",
  "Install Porch on your iPhone or Android phone, accept your invitation and get ready for calls.",
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
          Someone in your family has invited you to use Porch. It’s still a test app, so installing it
          takes an extra step. Follow the instructions for your phone below, then open your invitation.
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
                  First, tap <UI>Get</UI> to install Apple’s free TestFlight app. You don’t need to open it.
                </>
              ),
            },
            {
              name: "Porch on TestFlight",
              href: testFlight,
              qr: qrFor(testFlight),
              device: "your iPhone",
              how: (
                <>
                  Next, open this link and tap <UI>Accept</UI>, then <UI>Install</UI>.
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
                  First, email me at <Email /> with the Google account email address you use in Google Play.
                  It doesn’t have to be a Gmail address. I’ll add it to the test so you can install Porch.
                </>
              ),
            },
            {
              name: "Porch on Google Play",
              href: playTesting,
              qr: qrFor(playTesting),
              device: "your Android phone",
              how: (
                <>
                  After I’ve added your account, open this link, accept the test invitation and tap{" "}
                  <UI>Install</UI>.
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
              sent: "A link from the person who invited you, or a QR code on your loved one’s tablet.",
              device: "your own phone",
              how: "Open it on your phone after installing Porch. Text or email invitations work once and expire after 24 hours.",
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
          On your phone, open the invitation link you received by text or email. If the person setting up
          Porch is showing you a QR code on their tablet, scan it with your phone’s Camera instead.
        </li>
        <li>
          When Porch opens, tap <UI>Join family</UI>.
        </li>
        <li>
          If the link opens a web page instead of the app, tap <UI>Open invitation in Porch</UI>,
          then tap <UI>Join family</UI>.
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
          When Porch asks, allow notifications and microphone access. Otherwise, you may miss calls or
          people won’t hear you. Also check that Focus, Do Not Disturb and the Ring/Silent switch aren’t
          silencing calls.
        </p>
        <h3>On an Android phone</h3>
        <p>
          At the top of Porch, find <UI>Ring when Porch is closed</UI>. Tap <UI>Allow</UI> and
          approve the requested permissions. Then, under <UI>Show calls on the lock screen</UI>, tap{" "}
          <UI>Open settings</UI> and allow full-screen notifications.
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
                If the link opens a web page, tap <UI>Open invitation in Porch</UI>. If that doesn’t work,
                tap <UI>Copy invitation</UI>. Open Porch and choose <UI>I’m joining my family</UI>.
                Paste the link into <UI>Porch invitation</UI> on iPhone or <UI>Invitation link</UI> on Android,
                then tap <UI>Join family</UI>.
              </p>
            ),
          },
          {
            q: "My invitation stopped working.",
            a: <p>Invitations work once and expire after 24 hours. Ask whoever invited you for a new one.</p>,
          },
          {
            q: "My loved one’s key for me still calls my regular phone.",
            a: (
              <p>
                The keypad button should switch to your Porch app if your invitation used the same name.
                If it still calls your regular phone, ask the person who set it up to open caregiver mode,
                go to <UI>People</UI>, tap your button, then <UI>Porch app</UI>. Tap <UI>Choose from Family on Porch</UI> and select you.
              </p>
            ),
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
                Ask whoever set up your loved one’s tablet to make sure it’s charged, connected to Wi-Fi
                and showing the Porch clock.
              </p>
            ),
          },
          {
            q: "How do I get help?",
            a: (
              <p>
                Tell me what happened and whether you use an iPhone or Android. If there’s an error, a
                screenshot helps. You can <Contact />.
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
          Install Porch on your iPhone or Android phone, join your loved one’s family group and
          make sure you can receive calls.
        </p>
      }
      aside={
        <>
          Setting up the tablet your loved one will use? Follow the <Link href="/pilot/ios">iPad guide</Link> or{" "}
          <Link href="/pilot/android">Android tablet guide</Link> instead.
        </>
      }
      parts={parts}
    />
  );
}
