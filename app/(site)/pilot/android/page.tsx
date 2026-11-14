import Link from "next/link";
import { Chain, Choices, Contact, Email, Guide, guideMetadata, Links, Questions, Says, StepVideo, Tip, UI, type GuidePart, type KitPart } from "../_guide/parts";
import { playTesting, qrFor } from "../links";
import { shopping } from "../shopping";

export const metadata = guideMetadata(
  "Set up Porch on an Android tablet | HelloPorch",
  "Install Porch on an Android tablet, connect a big-button phone and invite family members.",
);

const kit: KitPart[] = [
  { name: "An Android tablet", rule: "Android 15 or later", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the tablet", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "A USB-C hub", ...shopping.hub, photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Optional", ...shopping.stand, photo: "/pilot/stand.jpg" },
];

const parts: GuidePart[] = [
  {
    id: "before",
    title: "Before you start",
    body: (
      <>
        <p>
          Porch is still being tested, so you’ll install it through Google Play’s testing program.
          Start with these steps in order.
        </p>
        <Links
          lettered
          items={[
            {
              name: "Email me the tablet’s Google account",
              how: (
                <>
                  First, email me at <Email /> with the Google account address used in Google Play on your
                  loved one’s tablet. It doesn’t have to be a Gmail address. I’ll add it to the test so you can install Porch.
                </>
              ),
            },
            {
              name: "Porch on Google Play",
              href: playTesting,
              qr: qrFor(playTesting),
              device: "your loved one’s tablet",
              how: (
                <>
                  After I’ve added the account, open this link on the tablet, accept the test invitation and tap{" "}
                  <UI>Install</UI>.
                </>
              ),
            },
            {
              name: "Your private setup link",
              sent: "I’ll email or text it to you.",
              device: "your loved one’s tablet only",
              how: "Use this on your loved one’s tablet. It works once and expires after 14 days.",
            },
          ]}
        />
        <p>
          You’ll add Porch to your own phone later in setup. The <Link href="/pilot/phone">phone guide</Link>{" "}
          has instructions for iPhones and Android phones.
        </p>
        <Tip>
          <p>Set aside about 30 minutes once you have everything. Keep the tablet, corded phone,
            Cell2Jack and your own phone nearby.</p>
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
          <strong>Check the Android version.</strong> Open <UI>Settings</UI>, then <UI>About tablet</UI>.
          Porch needs Android 15 or later. Install any available system updates.
        </li>
        <li>
          <strong>Sign in to Google Play</strong> with the Google account you sent me.
        </li>
        <li>
          <strong>Have your setup link ready on the tablet.</strong> Open it from your email or messages.
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
          caption="Watch how to install and set up Porch on the tablet."
        />
        <ol>
          <li>
            After I’ve added your Google account to the test, open{" "}
            <a href={playTesting}>the Porch test link</a> on the tablet. Accept the invitation, then
            tap <UI>Install</UI> in Google Play. Porch will appear with your other apps.
          </li>
          <li>
            Tap your private setup link on the tablet your loved one will use. Porch opens and asks{" "}
            <UI>Who is this Porch for?</UI>
          </li>
          <li>
            Enter a name your family will recognize, such as Grandpa Joe, and tap <UI>Continue</UI>.
          </li>
          <li>Choose a six-digit caregiver PIN and enter it twice. You’ll use it to change Porch’s settings, so keep it somewhere safe.</li>
          <li>
            Tap <UI>Get number</UI>. Porch will assign a phone number people can call. When it appears, tap{" "}
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
          When Porch shows <UI>Connect the phone</UI>, follow the steps below. Your loved one will press
          the corded phone’s buttons to call and answer. Your loved one will see and hear callers on the tablet and speak into the tablet’s microphone,
          not the phone receiver.
        </p>
        <Chain label="How it connects" items={["Corded phone", "Cell2Jack", "USB-C hub", "Tablet"]} />
        <ol>
          <li>Plug the phone’s cord into the Cell2Jack. Then plug the Cell2Jack’s USB cable into the hub.</li>
          <li>Connect the hub to the tablet, then plug the tablet’s charger into the hub’s charging port.</li>
          <li>
            When Android asks whether Porch can use the Cell2Jack, select the option to{" "}
            <strong>always open Porch</strong> and tap <UI>OK</UI>. If you miss the prompt, tap{" "}
            <UI>Allow Porch to use the Cell2Jack</UI> in Porch.
          </li>
          <li>
            When Porch asks, lift the receiver and press a button, such as 5. The tablet should say{" "}
            <Says>Porch heard 5. Now put the receiver back.</Says>
          </li>
          <li>
            Hang up. Porch says <Says>Porch heard you hang up. The phone is ready.</Says> Tap <UI>Continue</UI>.
          </li>
        </ol>
        <Tip label="If the phone keys don’t respond">
          <ul>
            <li>Unplug the Cell2Jack, then plug it back in. If Android asks, choose to always open Porch.</li>
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
            <strong>On your phone:</strong> allow notifications and the other permissions Porch needs for calls.
            See <Link href="/pilot/phone#ring">Let calls ring your phone</Link>.
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
    body: (
      <>
        <p>
          You can invite family and friends from Porch on your phone, now or later. Send each person
          their own invitation along with the <Link href="/pilot/phone">phone guide</Link> so they know how to join.
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
            Enter their name. If they already have a keypad button, use the same name so it can connect
            to their Porch app when they join.
          </li>
          <li>
            Choose whether they can use <UI>Audio drop-in</UI> or <UI>Video drop-in</UI>. Drop-in lets
            them connect without your loved one answering; turn these off if calls should ring instead.
            Turn on <UI>Caregiver mode</UI> only if they should be able to change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI>, send it by text or email, then tap <UI>Done</UI>.
          </li>
        </ol>
        <p>
          Before inviting someone with an Android phone, send me the email address they use for Google Play
          so I can add them to the test. Invitations work once and expire after 24 hours. You can make a new
          invitation if one expires.
        </p>
        <Tip label="Adding people later">
          <p>
            You can invite someone whenever they’re ready, from your phone as above, or on the tablet: open caregiver
            mode, then <UI>People</UI>, and tap <UI>Add someone</UI> under the keypad. People you invite with{" "}
            <UI>Caregiver mode</UI> turned on can invite others too.
          </p>
        </Tip>
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
        <p>
          You can assign any key, including * and #, to call someone, answer or hang up, turn video
          on or off, or play messages. By default, 0 answers and hangs up, 9 turns video on or off, and the
          other keys are unassigned. You can change them all.
        </p>
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI> and tap an empty key, such as 1.
          </li>
          <li>
            If they’ve joined, tap their name under <UI>On Porch</UI>. For anyone else, type their name or tap{" "}
            <UI>Choose from Contacts</UI>, then tap <UI>Next</UI>.
          </li>
          <li>
            Choose <UI>Phone</UI>, <UI>Porch app</UI> or both, then tap <UI>Next</UI>. With both, Porch rings
            their app first and their phone after 20 seconds.
          </li>
          <li>
            Check the key. You can add a photo or pick a color. Tap <UI>Add to key 1</UI>.
          </li>
          <li>
            If you chose <UI>Porch app</UI>, send them the invite from the next screen, then tap <UI>Done</UI>.
            Repeat for each key.
          </li>
        </ol>
        <p>
          To have a key answer and hang up, turn video on or off, or play messages, tap{" "}
          <UI>Use key 1 for something else</UI> on the first screen.
        </p>
        <h3>When someone joins Porch later</h3>
        <p>
          You can put someone on a button before they install Porch. Start with their name and regular phone
          number. When they join using an invitation with the same name, Porch automatically switches their key
          to call the app. Their phone number stays as a backup if they miss a call.
        </p>
        <p>
          If the key doesn’t switch (for example, because two people share a name or the tablet was offline
          for more than a day), open <UI>People</UI>, tap their key, then <UI>Choose from Family on Porch</UI>
          and select them.
        </p>
        <StepVideo
          name="android-switch"
          label="Video: switching a key from someone’s phone number to their Porch app by hand"
          caption="Switching key 1 from Sarah’s phone number to her Porch app by hand."
        />
      </>
    ),
  },
  {
    id: "language",
    title: "Change the language (optional)",
    body: (
      <>
        <p>
          Porch starts in English. If your loved one prefers another language, you can change what
          they see and hear on the tablet. Caregiver mode and family phones will still use English.
        </p>
        <p>You can choose:</p>
        <Choices
          label="Languages you can choose"
          items={[
            { name: "English" },
            { name: "Mandarin", note: "Traditional or simplified characters" },
            { name: "Cantonese" },
            { name: "Spanish" },
            { name: "Tagalog" },
            { name: "Korean" },
          ]}
        />
        <StepVideo
          name="android-language"
          label="Video: changing the tablet language and voice"
          caption="Changing the tablet’s language to Spanish and choosing a voice."
        />
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>Display &amp; voice</UI>. Under <UI>Bedside language</UI>, choose your loved one’s language.
          </li>
          <li>
            Under <UI>Announcement voice</UI>, choose a voice. Tap <UI>Preview announcement</UI>
            to hear how it sounds.
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
      <>
        <p>
          For more about Porch’s features and settings, see the <Link href="/pilot/features">features guide</Link>.
        </p>
        <Questions
          items={[
            {
              q: "The phone’s keys don’t do anything.",
              a: (
                <p>
                  Lift the receiver before pressing a key. Check that the switch on the phone is set to <UI>T</UI> or{" "}
                  <UI>Tone</UI>. Then open caregiver mode, <UI>This tablet</UI>, and run <UI>Connect the phone</UI> again.
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
                  Tell me what happened and which device you were using. If there’s an error, a photo
                  of the screen helps. You can <Contact />.
                </p>
              ),
            },
          ]}
        />
      </>
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
          This guide walks you through installing Porch on your loved one’s tablet, connecting the
          big-button phone and adding family members.
        </p>
      }
      aside={
        <>
          If your loved one uses an iPad, follow the <Link href="/pilot/ios">iPad setup guide</Link>. For family
          members’ phones, see the <Link href="/pilot/phone">phone guide</Link>.
        </>
      }
      kit={{
        intro: "The Cell2Jack connects the corded phone to the tablet through the USB-C hub. Prices are approximate.",
        parts: kit,
        ready: [
          "The Wi-Fi password where your loved one lives.",
          "Your private setup link, from me.",
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
