import Link from "next/link";
import { Chain, Contact, Email, Guide, guideMetadata, Links, Questions, Says, StepVideo, Tip, UI, type GuidePart, type KitPart } from "../_guide/parts";
import { playTesting, qrFor } from "../links";
import { shopping } from "../shopping";

export const metadata = guideMetadata(
  "Set up Porch on an Android tablet | HelloPorch",
  "Set up your loved one’s Android tablet, connect the corded phone and add family members to Porch.",
);

const kit: KitPart[] = [
  { name: "An Android tablet", rule: "Android 15 or later", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", rule: "Set to tone dialing", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the tablet", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "A USB-C hub", rule: "With a port for the tablet’s charger", ...shopping.hub, photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Optional", ...shopping.stand, photo: "/pilot/stand.jpg" },
];

const parts: GuidePart[] = [
  {
    id: "before",
    title: "Before you start",
    body: (
      <>
        <p>During the pilot, Porch is a test app. You’ll open two links on your loved one’s tablet.</p>
        <Links
          items={[
            {
              name: "Porch on Google Play",
              href: playTesting,
              qr: qrFor(playTesting),
              sent: "I’ll send you this link.",
              device: "your loved one’s tablet",
              how: (
                <>
                  First email me at <Email /> the address of the Google account signed in to Google Play on the
                  tablet. It’s usually a Gmail address, but any Google account works. Once I’ve added it, open this
                  link on the tablet, accept the invitation and tap <UI>Install</UI>.
                </>
              ),
            },
            {
              name: "Your private setup link",
              sent: "I’ll email or text it to you.",
              device: "your loved one’s tablet only",
              how: "It works on one tablet and expires after 14 days.",
            },
          ]}
        />
        <p>
          You’ll also add Porch to your own phone partway through. The <Link href="/pilot/phone">phone guide</Link>{" "}
          covers phones, for you and the rest of the family.
        </p>
        <Tip>
          <p>Allow about 30 minutes. Have the tablet, corded phone and your own phone nearby.</p>
          <p>
            If you get stuck at any point, <Contact />.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "tablet",
    title: "Get the tablet ready",
    on: ["bedside"],
    body: (
      <ol>
        <li>
          <strong>Charge it and connect it to Wi-Fi.</strong> If you’re setting up at your loved one’s home, use their Wi-Fi.
        </li>
        <li>
          <strong>Check the Android version.</strong> Open <UI>Settings</UI>, then <UI>About tablet</UI>. Porch needs
          Android 15 or later. Install any system update the tablet offers.
        </li>
        <li>
          <strong>Sign in to Google Play</strong> with the Google account you sent me.
        </li>
        <li>
          <strong>Make sure you can open your setup link on it,</strong> from your email or texts on the tablet.
        </li>
      </ol>
    ),
  },
  {
    id: "install",
    title: "Install and set up Porch",
    on: ["bedside"],
    body: (
      <>
        <StepVideo
          name="android-setup"
          label="Video: installing Porch and setting up your loved one’s Porch on the tablet"
          caption="Installing Porch, opening your setup link and setting up your loved one’s Porch."
        />
        <ol>
          <li>
            On the tablet, open{" "}
            {playTesting ? <a href={playTesting}>Porch’s Google Play test</a> : "the Google Play test link I sent you"}.
            Accept the invitation to test Porch, then tap <UI>Install</UI> in Google Play. Porch appears with the
            tablet’s apps.
          </li>
          <li>
            Tap your private setup link on the tablet your loved one will use. Porch opens and asks{" "}
            <UI>Who is this Porch for?</UI>
          </li>
          <li>
            Enter the name family members use, such as Grandpa Joe, and tap <UI>Continue</UI>.
          </li>
          <li>Choose a six-digit caregiver PIN. Enter it twice and keep it somewhere safe.</li>
          <li>
            Tap <UI>Get number</UI> to get a phone number for your loved one’s Porch. When it appears, tap{" "}
            <UI>Continue</UI>.
          </li>
          <li>
            Tap <UI>Continue</UI>. For the camera and microphone, choose <UI>While using the app</UI>. Allow
            notifications.
          </li>
          <li>
            Choose <UI>Corded phone</UI>. If you’re waiting for a part, tap <UI>Do this later</UI>.
          </li>
        </ol>
      </>
    ),
  },
  {
    id: "phone",
    title: "Connect the big-button phone",
    on: ["bedside"],
    body: (
      <>
        <p>
          When Porch shows <UI>Connect the phone</UI>, follow the steps below. You’ll use the corded phone’s keys to
          make and answer calls. You’ll see and hear the caller on the tablet and speak into the tablet’s microphone.
        </p>
        <Chain label="How it connects" items={["Corded phone", "Cell2Jack", "USB-C hub", "Tablet"]} />
        <ol>
          <li>Plug the phone’s cord into the Cell2Jack, and the Cell2Jack’s USB cable into the hub.</li>
          <li>Plug the hub into the tablet, and the tablet’s charger into the hub’s charging port.</li>
          <li>
            When Android asks whether Porch can use the Cell2Jack, check the box to <strong>always open Porch</strong>{" "}
            and tap <UI>OK</UI>. If you miss the prompt, tap <UI>Allow Porch to use the Cell2Jack</UI>.
          </li>
          <li>
            When Porch asks, lift the receiver and press a key, such as 5. Listen for{" "}
            <Says>Porch heard 5. Now put the receiver back.</Says>
          </li>
          <li>
            Hang up. Porch says <Says>Porch heard you hang up. The phone is ready.</Says> Tap <UI>Continue</UI>.
          </li>
        </ol>
        <Tip label="If the phone keys don’t respond">
          <ul>
            <li>Unplug the Cell2Jack and plug it back in. When Android asks, choose to always open Porch.</li>
            <li>Check that the switch on the phone is set to <UI>T</UI> or <UI>Tone</UI>.</li>
            <li>The keys only work while the receiver is lifted.</li>
            <li>
              If the Cell2Jack says the phone isn’t connected when you lift the receiver, press a key to stop the announcement.
            </li>
          </ul>
        </Tip>
        <p>
          If you skipped this step, your loved one can use the touchscreen. To connect the phone later, open
          caregiver mode, tap <UI>This tablet</UI>, then <UI>Connect the phone</UI>.
        </p>
      </>
    ),
  },
  {
    id: "your-phone",
    title: "Add your phone",
    on: ["bedside", "phone"],
    body: (
      <>
        <StepVideo
          name="android-your-phone"
          label="Video: adding your phone with the QR code on the tablet"
          caption="Adding your phone with the QR code on the tablet."
        />
        <ol>
          <li>
            <strong>On your phone:</strong> install Porch. See <Link href="/pilot/phone#get">Get Porch</Link> in the phone
            guide, for an Android phone or an iPhone.
          </li>
          <li>
            <strong>On the tablet:</strong> type your name, then tap <UI>Show QR code</UI>.
          </li>
          <li>
            <strong>On your phone:</strong> open the Camera app and point it at the code. Tap the link that appears,
            then tap <UI>Join family</UI> in Porch.
          </li>
          <li>
            <strong>On your phone:</strong> allow what Porch asks for, so calls can ring. See{" "}
            <Link href="/pilot/phone#ring">Let calls ring your phone</Link>.
          </li>
          <li>
            <strong>On the tablet:</strong> it says your phone joined. Tap <UI>Continue</UI>, then <UI>Back to the clock</UI>.
          </li>
        </ol>
      </>
    ),
  },
  {
    id: "family",
    title: "Invite family members",
    on: ["phone"],
    body: (
      <>
        <p>
          Invite family and friends from Porch on your phone, now or any time later. Each person gets their own
          invitation. Send it with the <Link href="/pilot/phone">phone guide</Link>, which shows them how to get Porch
          and join.
        </p>
        <StepVideo
          name="android-invite"
          label="Video: inviting a relative from your phone"
          caption="Inviting a relative from your phone."
        />
        <ol>
          <li>
            In Porch on your phone, tap <UI>Caregiver mode</UI>, enter the PIN and tap <UI>Open caregiver mode</UI>.
            On an iPhone, <UI>Caregiver mode</UI> is under the person icon in the top right corner.
          </li>
          <li>
            Open <UI>Family</UI> and tap <UI>Invite someone</UI>.
          </li>
          <li>
            Enter their name. Turn off <UI>Audio drop-in</UI> or <UI>Video drop-in</UI> if their calls should ring
            first. Turn on <UI>Caregiver mode</UI> for people who should change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI> and send it by text or email. Then tap <UI>Done</UI>.
          </li>
        </ol>
        <p>
          Each invitation works once and expires after 24 hours. If one runs out, make a new one the same way.
          Relatives with an Android phone need me to add their Google account to the Google Play test first, so send me
          their email before you invite them.
        </p>
        <Tip label="Adding people later">
          <p>
            You can invite someone whenever they’re ready, from your phone as above, or on the tablet: open caregiver
            mode, then <UI>People</UI>, and tap <UI>Invite someone</UI> under the keypad. People you invite with{" "}
            <UI>Caregiver mode</UI> turned on can invite others too.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "keypad",
    title: "Set up the phone’s number keys",
    on: ["bedside"],
    body: (
      <>
        <StepVideo
          name="android-keypad"
          label="Video: putting a family member on key 1"
          caption="Putting a family member who has joined on key 1."
        />
        <p>
          Any key, including * and #, can <UI>Call a person</UI>, <UI>Answer / decline / hang up</UI>,{" "}
          <UI>Turn video off / on</UI> or <UI>Play / stop messages</UI>. To start, 0 answers and hangs up, 9 turns video
          off and on, and the other keys have no action. You can change any of them.
        </p>
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI> and tap the key you want to set up, such as 1. To have it call someone, choose{" "}
            <UI>Call a person</UI>.
          </li>
          <li>
            If they’ve joined, tap <UI>Choose from Family on Porch</UI> and choose them. For anyone else, type their
            name or tap <UI>Choose from Contacts</UI>.
          </li>
          <li>
            Under <UI>Calls start as</UI>, choose <UI>Video</UI> or <UI>Voice</UI>.
          </li>
          <li>
            To try their regular phone when they miss a Porch call, turn on <UI>Call their phone</UI> and enter their{" "}
            <UI>Primary number</UI>. Porch tries it after 20 seconds.
          </li>
          <li>
            Tap <UI>Save</UI>. Repeat for each key.
          </li>
        </ol>
      </>
    ),
  },
  {
    id: "language",
    title: "Change the language or voice",
    on: ["bedside"],
    body: (
      <>
        <StepVideo
          name="android-language"
          label="Video: changing the bedside language and voice"
          caption="Switching the bedside to Spanish and choosing a voice."
        />
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>Display &amp; voice</UI>. Under <UI>Bedside language</UI>, choose English, Mandarin, Cantonese,
            Spanish, Tagalog or Korean.
          </li>
          <li>
            To pick a voice, tap the menu under <UI>Announcement voice</UI>. <UI>Preview announcement</UI> lets you
            hear it.
          </li>
          <li>
            Tap <UI>Save</UI>, then <UI>Back to clock</UI>.
          </li>
        </ol>
      </>
    ),
  },
  {
    id: "settings",
    title: "Tablet settings that help",
    on: ["bedside"],
    body: (
      <ul>
        <li>
          <strong>Make Porch the tablet’s home screen.</strong> On the clock, tap{" "}
          <UI>Make Porch this tablet’s home screen</UI>, choose <UI>Porch</UI> and confirm. The tablet then opens Porch
          when it restarts or when someone presses Home. To reach Android’s own settings later, open caregiver mode,
          then <UI>This tablet</UI> and <UI>Tablet settings</UI>.
        </li>
        <li>
          <strong>Keep the tablet plugged in.</strong> Plug its charger into the hub. Porch keeps the screen on while
          the clock is showing.
        </li>
        <li>
          <strong>Turn the volume up</strong> so your loved one hears calls and announcements.
        </li>
        <li>
          <strong>Let Porch run in the background.</strong> In <UI>Settings</UI>, open <UI>Apps</UI>, then{" "}
          <UI>Porch</UI>, then <UI>Battery</UI>, and choose <UI>Unrestricted</UI>. The names vary a little by brand.
        </li>
        <li>
          <strong>Keep Porch updated.</strong> Google Play updates it on its own. Leave automatic updates on.
        </li>
      </ul>
    ),
  },
  {
    id: "help",
    title: "If something isn’t working",
    body: (
      <Questions
        items={[
          {
            q: "The phone’s keys don’t do anything.",
            a: (
              <p>
                Lift the receiver before pressing a key. Check that the switch on the phone is set to <UI>T</UI> or{" "}
                <UI>Tone</UI>. Then open caregiver mode, <UI>This tablet</UI>, and run <UI>Connect the phone</UI> again, or tap{" "}
                <UI>Retry phone connection</UI>.
              </p>
            ),
          },
          {
            q: "My phone says the tablet isn’t checking in.",
            a: (
              <p>
                Check that the tablet is on, plugged in and connected to Wi-Fi. Open Porch and leave the clock showing.
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
            q: "The setup link opens a web page instead of Porch.",
            a: (
              <p>
                Tap <UI>Open setup in Porch</UI>. If that doesn’t work, tap <UI>Copy setup link</UI>, open Porch, tap{" "}
                <UI>Set up Porch for someone</UI>, paste the link into <UI>Setup link</UI> and tap <UI>Continue</UI>.
              </p>
            ),
          },
          {
            q: "Porch says no voice is available for a language.",
            a: (
              <p>
                Add one in Android’s <UI>Settings</UI>, under <UI>Accessibility</UI>, then{" "}
                <UI>Text-to-speech output</UI>.
              </p>
            ),
          },
          {
            q: "The setup link stopped working.",
            a: <p>It works once and expires after 14 days. Ask me for a new one.</p>,
          },
          {
            q: "Someone can’t call my loved one’s Porch number.",
            a: (
              <p>
                Save their number to a key or open <UI>Calls</UI> in caregiver mode. Tap <UI>Blocked numbers</UI>, then{" "}
                <UI>Allow</UI> next to the number.
              </p>
            ),
          },
          {
            q: "How do I add someone later?",
            a: (
              <p>
                Any time, from Porch on your phone: open caregiver mode, then <UI>Family</UI>, and tap{" "}
                <UI>Invite someone</UI>. Send them the invitation and the <Link href="/pilot/phone">phone guide</Link>.
              </p>
            ),
          },
          {
            q: "How do I get help?",
            a: (
              <p>
                Tell me what happened and which device you were using. You can <Contact />. If there’s an error on the
                screen, a photo helps.
              </p>
            ),
          },
        ]}
      />
    ),
  },
];

export default function AndroidGuide() {
  return (
    <Guide
      eyebrow="Porch pilot guide"
      title={
        <>
          Set up Porch on an <em>Android tablet</em>
        </>
      }
      lede={
        <p>
          Set up the tablet your loved one will use, connect their big-button phone and add Porch to your own phone.
        </p>
      }
      aside={
        <>
          If your loved one uses an iPad, follow the <Link href="/pilot/ios">iPad setup guide</Link>. For family
          members’ phones, see the <Link href="/pilot/phone">phone guide</Link>.
        </>
      }
      kit={{
        intro: "The Cell2Jack connects the corded phone to the tablet through the USB-C hub.",
        parts: kit,
        ready: [
          "Wi-Fi where your loved one lives, and its password.",
          "Your private setup link, and the link to join Porch’s Google Play test. I’ll send you both.",
          "Your own iPhone or Android phone.",
          <>
            A few photos of the people your loved one calls most, to print as labels for their keys with the{" "}
            <Link href="/labels">phone button label maker</Link>.
          </>,
        ],
      }}
      parts={parts}
      bedside="tablet"
    />
  );
}
