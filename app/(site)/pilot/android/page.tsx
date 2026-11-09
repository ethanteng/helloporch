import Link from "next/link";
import { Chain, Contact, Email, Guide, guideMetadata, Questions, Says, StepVideo, Tip, UI, type GuidePart, type KitPart } from "../_guide/parts";
import { shopping } from "../shopping";

export const metadata = guideMetadata(
  "Set up Porch on an Android tablet | HelloPorch",
  "Set up your loved one’s Android tablet, connect the corded phone and add family members to Porch.",
);

// Porch's Google Play testing page, the same one invitation pages use. Until it's set, the guide says I'll send it.
const playTesting = process.env.NEXT_PUBLIC_PLAY_TESTING_URL;
// For a caregiver with an iPhone: Porch's public TestFlight link, and Apple's TestFlight app.
const testFlight = process.env.NEXT_PUBLIC_TESTFLIGHT_URL;
const testFlightApp = "https://apps.apple.com/app/testflight/id899247664";

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
        <p>
          During the pilot, I’ll add your Google account to the Porch test before you can install the app.
        </p>
        <ol>
          <li>
            <strong>Email me at <Email />.</strong> Send the email address you use in Google Play on the tablet, usually
            a Gmail address. If you have an Android phone, include the address you use on your phone too.
          </li>
          <li>
            I’ll send you two links. Use the Google Play test link to install Porch. Use the private setup link to
            set up one tablet. The setup link expires after 14 days.
          </li>
        </ol>
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
      </ol>
    ),
  },
  {
    id: "install",
    title: "Install and set up Porch",
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
    body: (
      <>
        <StepVideo
          name="android-your-phone"
          label="Video: adding your phone with the QR code on the tablet"
          caption="Adding your phone with the QR code on the tablet."
        />
        <ol>
          <li>
            Install Porch on your phone first. On an Android phone, join the test and install Porch the same way you
            did on the tablet. On an iPhone, install Apple’s <a href={testFlightApp}>TestFlight app</a>, then open{" "}
            {testFlight ? <a href={testFlight}>Porch’s TestFlight link</a> : "the TestFlight link I sent you"} and tap{" "}
            <UI>Accept</UI>, then <UI>Install</UI>.
          </li>
          <li>
            On the tablet, type your name, then tap <UI>Show QR code</UI>.
          </li>
          <li>Open the Camera app on your phone and point it at the code. Tap the link that appears.</li>
          <li>
            Porch opens on your phone. Tap <UI>Join family</UI>.
          </li>
          <li>
            The tablet says your phone joined. Tap <UI>Continue</UI>, then <UI>Back to the clock</UI>.
          </li>
          <li id="ring">
            On an Android phone, look at the top of Porch so calls can ring while it’s closed. Under{" "}
            <UI>Ring when Porch is closed</UI>, tap <UI>Allow</UI>. Under <UI>Show calls on the lock screen</UI>, tap{" "}
            <UI>Open settings</UI> and allow full-screen notifications.
          </li>
        </ol>
      </>
    ),
  },
  {
    id: "keypad",
    title: "Set up the phone’s number keys",
    body: (
      <>
        <StepVideo
          name="android-keypad"
          label="Video: putting a family member on key 1"
          caption="Putting a family member who has joined on key 1."
        />
        <p>Keys 1 to 8 call people. Key 0 answers and hangs up, and key 9 turns the camera off and on.</p>
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI> and tap a key, such as 1. Choose <UI>Call a person</UI>.
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
    id: "family",
    title: "Invite family members",
    body: (
      <>
        <StepVideo
          name="android-invite"
          label="Video: inviting a relative from your phone"
          caption="Inviting a relative from your phone."
        />
        <ol>
          <li>
            In Porch on your phone, scroll down and tap <UI>Caregiver mode</UI>. Enter the PIN and tap{" "}
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
            Tap <UI>Create invitation</UI>, then <UI>Share invitation</UI>, and send it by text or email. If they’re
            next to you, they can scan the code. Then tap <UI>Done</UI>.
          </li>
        </ol>
        <p>
          Each invitation works once and expires after 24 hours. Relatives with an Android phone need to be in the
          Google Play test first, so send me their Google account before you invite them.
        </p>
      </>
    ),
  },
  {
    id: "language",
    title: "Change the language or voice",
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
            q: "My phone doesn’t ring when my loved one calls.",
            a: (
              <p>
                Open Porch on your phone and follow any card at the top, such as <UI>Ring when Porch is closed</UI>.
                Check that Porch’s notifications are on in your phone’s settings, and that Do Not Disturb isn’t on.
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
            q: "My phone won’t join from the QR code.",
            a: (
              <p>
                If the link opens a web page, tap <UI>Open invitation in Porch</UI>. Or tap <UI>Copy invitation</UI>,
                open Porch, tap <UI>I’m joining my family</UI>, paste it into <UI>Invitation link</UI> and tap{" "}
                <UI>Join family</UI>. You can also tap <UI>Send the invitation instead</UI> on the tablet and send the
                link to your phone.
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
            q: "An invitation or the setup link stopped working.",
            a: (
              <p>
                Family invitations work once and expire after 24 hours. Create a new invitation in caregiver mode. If the
                setup link for the tablet has expired, ask me for a new one.
              </p>
            ),
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
          If your loved one uses an iPad, follow the{" "}
          <Link href="/pilot/ios">iPad and iPhone setup guide</Link>.
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
    />
  );
}
