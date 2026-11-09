import Link from "next/link";
import { Contact, Email, Guide, guideMetadata, Links, Questions, StepVideo, Tip, UI, type GuidePart } from "../_guide/parts";
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
        <p>During the pilot, Porch is a test app. Get it from the link for your phone, then open your invitation.</p>
        <Links
          items={[
            {
              name: "Porch on TestFlight",
              href: testFlight,
              qr: qrFor(testFlight),
              sent: "I’ll send you this link.",
              device: "an iPhone",
              how: (
                <>
                  First install Apple’s free <a href={testFlightApp}>TestFlight app</a> from the App Store. Then open
                  this link and tap <UI>Accept</UI>, then <UI>Install</UI>.
                </>
              ),
            },
            {
              name: "Porch on Google Play",
              href: playTesting,
              qr: qrFor(playTesting),
              sent: "I’ll send you this link.",
              device: "an Android phone",
              how: (
                <>
                  First email me at <Email /> the address of the Google account you use in Google Play. It’s usually a
                  Gmail address, but any Google account works. Once I’ve added it, open this link, accept the
                  invitation and tap <UI>Install</UI>.
                </>
              ),
            },
            {
              name: "Your invitation",
              sent: "From a caregiver, or the code on your loved one’s iPad or tablet.",
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
    id: "invite",
    title: "Invite family members",
    body: (
      <>
        <p>Caregivers invite relatives from their phone, one invitation per person.</p>
        <h3>On an iPhone</h3>
        <StepVideo
          name="ios-invite"
          label="Video: inviting a relative from an iPhone"
          caption="Inviting a relative from an iPhone."
        />
        <ol>
          <li>
            In Porch, tap the person icon in the top right corner, then <UI>Caregiver mode</UI>. Enter the PIN and tap{" "}
            <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>Family</UI> and tap <UI>Invite someone</UI>.
          </li>
          <li>
            Enter their name. Turn off <UI>Audio drop-in</UI> or <UI>Video drop-in</UI> if their calls should ring
            first. Turn on <UI>Caregiver mode</UI> for people who should change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI>, send it by text or email, then tap <UI>Done</UI>.
          </li>
        </ol>
        <h3>On an Android phone</h3>
        <StepVideo
          name="android-invite"
          label="Video: inviting a relative from an Android phone"
          caption="Inviting a relative from an Android phone."
        />
        <ol>
          <li>
            In Porch, scroll down and tap <UI>Caregiver mode</UI>. Enter the PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>Family</UI> and tap <UI>Invite someone</UI>.
          </li>
          <li>
            Enter their name. Turn off <UI>Audio drop-in</UI> or <UI>Video drop-in</UI> if their calls should ring
            first. Turn on <UI>Caregiver mode</UI> for people who should change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI>, then <UI>Share invitation</UI>, and send it by text or email. If they’re
            next to you, they can scan the code. Then tap <UI>Done</UI>.
          </li>
        </ol>
        <p>
          Each invitation works once and expires after 24 hours. Send relatives this guide with their invitation.
          Relatives with an Android phone need me to add their Google account to the Google Play test first, so send me
          their email before you invite them.
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
            a: <p>Invitations work once and expire after 24 hours. Ask a caregiver for a new one.</p>,
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
          For everyone in the family, on an iPhone or an Android phone: get Porch, join your family and make sure
          calls ring.
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
