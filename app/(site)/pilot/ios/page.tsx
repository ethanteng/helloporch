import Link from "next/link";
import { Choices, Contact, FilmedVideo, Guide, guideMetadata, Links, Questions, Says, Screenshot, StepVideo, Tip, UI, type GuidePart, type KitPart } from "../_guide/parts";
import { qrFor, testFlight, testFlightApp } from "../links";
import { shopping } from "../shopping";

/** Filmed at home: plugging in the corded phone, Cell2Jack, Porch phone adapter and hub. */
const connectPhoneVideo =
  "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/How%20to%20connect%20phone%20to%20iPad%20compressed.mp4";

export const metadata = guideMetadata(
  "Set up Porch on an iPad | HelloPorch",
  "Install Porch on an iPad, connect a big-button phone and invite family members.",
);

const kit: KitPart[] = [
  { name: "An iPad", rule: "iPadOS 15 or later", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the iPad", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "The Porch phone adapter", rule: "I will mail it to you", ...shopping.adapter, photo: "/pilot/adapter.jpg" },
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
          Porch is still being tested, so you’ll install it through Apple’s free TestFlight app. On your loved
          one’s iPad, use these links in order.
        </p>
        <Links
          lettered
          items={[
            {
              name: "TestFlight on the App Store",
              href: testFlightApp,
              qr: qrFor(testFlightApp),
              device: "your loved one’s iPad",
              how: (
                <>
                  First, tap <UI>Get</UI> to install TestFlight. You don’t need to open it.
                </>
              ),
            },
            {
              name: "Porch on TestFlight",
              href: testFlight,
              qr: qrFor(testFlight),
              device: "your loved one’s iPad",
              how: (
                <>
                  Once TestFlight is installed, open this link and tap <UI>Accept</UI>, then <UI>Install</UI>.
                </>
              ),
            },
            {
              name: "Your private setup link",
              sent: "I’ll email or text it to you.",
              device: "your loved one’s iPad only",
              how: "Use this on your loved one’s iPad. It works once and expires after 14 days.",
            },
          ]}
        />
        <p>
          You’ll add Porch to your own phone later in setup. The <Link href="/pilot/phone">phone guide</Link>{" "}
          has instructions for iPhones and Android phones.
        </p>
        <p>
          I’ll mail you the <strong>Porch phone adapter</strong>, or bring it by if you’re in the Bay Area.
          You can set up Porch before it arrives and connect the corded phone later.
        </p>
        <Tip>
          <p>
            Allow about 30 minutes for setup. You’ll need the iPad, corded phone, Cell2Jack, Porch phone
            adapter and your own phone when you connect everything.
          </p>
          <p>
            If you get stuck at any point, <Contact />.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "ipad",
    title: "Get the iPad ready",
    body: (
      <>
        <ol>
          <li>
            <strong>Charge it and connect it to Wi-Fi.</strong> If you’re setting up at your loved one’s home, use their Wi-Fi.
          </li>
          <li>
            <strong>Update it.</strong> Open <UI>Settings</UI>, then <UI>General</UI> and <UI>Software Update</UI>.
            Porch needs iPadOS 15 or later.
          </li>
          <li>
            <strong>Check the date and time.</strong> Under <UI>Settings</UI>, <UI>General</UI>,{" "}
            <UI>Date &amp; Time</UI>, make sure <UI>Set Automatically</UI> is on.
          </li>
          <li>
            <strong>Sign in to the App Store</strong> with an Apple ID, so the iPad can install TestFlight.
          </li>
          <li>
            <strong>Have your setup link ready on the iPad.</strong> Open it from email or messages, or
            send it from your iPhone using AirDrop.
          </li>
        </ol>
        <Tip label="An older iPad?">
          <p>
            If your iPad has a Lightning charging port rather than USB-C, you’ll need a Lightning adapter
            with a charging port, such as{" "}
            <a href={shopping.lightningHub.href} target="_blank" rel="noopener noreferrer">
              this one on Amazon
            </a>{" "}
            ({shopping.lightningHub.price.toLowerCase()}). Not sure which one to get? Ask me before buying.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "install",
    title: "Install and set up Porch",
    body: (
      <>
        <StepVideo
          name="ios-setup"
          label="Video: installing Porch and setting up your loved one’s Porch on the iPad"
          caption="Watch how to install and set up Porch on the iPad."
        />
        <ol>
          <li>
            If you haven’t already, install <a href={testFlightApp}>TestFlight</a> on the iPad. Then open{" "}
            <a href={testFlight}>the Porch test link</a> and tap <UI>Accept</UI>, then <UI>Install</UI>.
            Porch will appear on the Home Screen.
          </li>
          <li>
            Tap your private setup link on the iPad your loved one will use. Porch opens and asks{" "}
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
            Tap <UI>Continue</UI> and allow the microphone and camera.
          </li>
          <li>
            Choose <UI>Corded phone</UI>. If the adapter hasn’t arrived yet, tap <UI>Do this later</UI>.
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
          the corded phone’s buttons to call and answer. Your loved one will see and hear callers on the iPad and speak into the iPad’s microphone,
          not the phone receiver.
        </p>
        <h3>Plug in the phone</h3>
        <FilmedVideo
          src={connectPhoneVideo}
          poster="ios-connect-phone"
          width={1920}
          height={1080}
          label="Video: connecting the corded phone to the iPad with the Cell2Jack, the Porch phone adapter and the hub"
          caption="Connecting the corded phone to the iPad with the Porch phone adapter."
        />
        <ol>
          <li>
            <strong>Plug the iPad’s charger into the hub first,</strong> then connect the hub to the iPad.
            This powers the iPad, adapter and Cell2Jack.
          </li>
          <li>Plug the phone’s cord into the Cell2Jack, and the Cell2Jack’s USB cable into the adapter.</li>
          <li>
            Plug the adapter’s USB-C cable into the hub. The adapter’s red light blinks, then stays on. That takes a few
            seconds.
          </li>
        </ol>
        <Tip label="If Porch says the iPad has an M chip">
          <p>
            Some newer iPads can connect without the adapter: an iPad Pro (2021 or later) or iPad Air
            (2022 or later) running iPadOS 16 or later. Only follow these steps if Porch offers the option
            at the bottom of <UI>Connect the phone</UI>:
          </p>
          <ol>
            <li>Plug the Cell2Jack’s USB cable straight into the hub.</li>
            <li>
              Tap <UI>Open Settings</UI> under that note. Turn on <UI>Cell2Jack USB Driver</UI>, then go back to Porch.
            </li>
            <li>
              Unplug the Cell2Jack from the hub for ten seconds and plug it back in. Porch shows{" "}
              <UI>The phone is connected.</UI>
            </li>
          </ol>
        </Tip>
        <h3>Test the phone</h3>
        <ol>
          <li>
            When Porch asks, lift the receiver and press a button, such as 3. The iPad should say{" "}
            <Says>Porch heard 3. Now put the receiver back.</Says>
          </li>
          <li>
            Hang up. Porch says <Says>Porch heard you hang up. The phone is ready.</Says> Tap <UI>Continue</UI>.
          </li>
        </ol>
        <Screenshot
          src="/pilot/screens/ipad-connect-phone.png"
          width={1600}
          height={1112}
          device="tablet"
          alt="The Connect the phone screen on an iPad, with a Step-by-step instructions link and the message: Porch heard 3. Now put the receiver back."
          caption="The phone check after pressing 3. Hang up next."
        />
        <Tip label="If the phone keys don’t respond">
          <ul>
            <li>Check the hub’s charger is plugged in, so the iPad can power the adapter and the Cell2Jack.</li>
            <li>
              If the adapter’s light keeps blinking, unplug the Cell2Jack from it for ten seconds and plug it back in.
            </li>
            <li>If the adapter’s light never comes on, try another USB-C cable. Some cables only charge.</li>
            <li>
              If you left the adapter out on an iPad with an M chip, tap <UI>Open Settings</UI> on{" "}
              <UI>Connect the phone</UI> and check that <UI>Cell2Jack USB Driver</UI> is on. Then unplug the Cell2Jack
              for ten seconds and plug it back in.
            </li>
            <li>Check that the switch on the phone is set to <UI>T</UI> or <UI>Tone</UI>.</li>
            <li>The keys only work while the receiver is lifted.</li>
            <li>
              If the Cell2Jack says the phone isn’t connected when you lift the receiver, press a key to stop the announcement.
            </li>
          </ul>
        </Tip>
        <p>
          If you skipped this step, your loved one can use the touchscreen. To connect the phone later, open
          caregiver mode, tap <UI>This iPad</UI>, then <UI>Connect the phone</UI>.
        </p>
      </>
    ),
  },
  {
    id: "your-phone",
    title: "Add your own phone",
    body: (
      <>
        <StepVideo
          name="ios-your-phone"
          label="Video: adding your phone with the QR code on the iPad"
          caption="Adding your iPhone with the QR code on the iPad."
        />
        <ol>
          <li>
            <strong>On your phone:</strong> if you have an iPhone, install TestFlight first, then Porch, as you did on
            the iPad. For an Android phone, see <Link href="/pilot/phone#get">Get Porch</Link> in the phone guide.
          </li>
          <li>
            <strong>On the iPad:</strong> type your name, then tap <UI>Show QR code</UI>.
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
            <strong>On the iPad:</strong> it says your phone joined. Tap <UI>Continue</UI>.
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
            You can invite someone whenever they’re ready, from your phone as above, or on the iPad: open caregiver
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
          name="ios-keypad"
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
            At the end of setup, tap <UI>Put people on the keypad</UI>. To return later, tap the gear
            on the clock, enter your PIN and choose <UI>Open caregiver mode</UI>.
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
          If the key doesn’t switch (for example, because two people share a name or the iPad was offline
          for more than a day), open <UI>People</UI>, tap their key, then <UI>Choose from Family on Porch</UI>
          and select them.
        </p>
        <StepVideo
          name="ios-switch"
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
          they see and hear on the iPad. Caregiver mode and family phones will still use English.
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
          name="ios-language"
          label="Video: changing the iPad language and voice"
          caption="Changing the iPad’s language to Spanish and choosing a voice."
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
    title: "iPad settings that help",
    body: (
      <ul>
        <li>
          <strong>Keep Porch open on the clock, and the iPad plugged in</strong> with the charger in the hub. Porch keeps
          the screen awake while the clock is showing. Drop-ins, and calls your loved one makes, need the clock open.
        </li>
        <li>
          <strong>Turn the volume up</strong> with the iPad’s side buttons. To check it, open caregiver mode, then{" "}
          <UI>Calls</UI> and <UI>Test sounds</UI>.
        </li>
        <li>
          <strong>Keep the iPad in Porch.</strong> To keep other apps from opening, go to <UI>Settings</UI>, then{" "}
          <UI>Accessibility</UI> and <UI>Guided Access</UI>. Leave <UI>Touch</UI> and <UI>Software Keyboards</UI> on.
          Pause Guided Access when you need to type in Porch.
        </li>
        <li>
          <strong>Keep Porch updated.</strong> Each test version lasts 90 days. In TestFlight, open Porch and turn on{" "}
          <UI>Automatic Updates</UI>, on the iPad and your iPhone.
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
                  Lift the receiver before pressing a key, and check that the charger is plugged into the hub and the
                  adapter’s red light is on. Then open caregiver mode, <UI>This iPad</UI>, and run{" "}
                  <UI>Connect the phone</UI> again. If you left the adapter out on an iPad with an M chip, tap{" "}
                  <UI>Open Settings</UI> there and check that <UI>Cell2Jack USB Driver</UI> is on.
                </p>
              ),
            },
            {
              q: "My phone says Porch isn’t ready.",
              a: (
                <p>
                  Check that the iPad is on, plugged in and connected to Wi-Fi. Open Porch and leave the clock showing.
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
              q: "Porch won’t open, or says it has expired.",
              a: (
                <p>
                  Each test version lasts 90 days. Open TestFlight and tap <UI>Update</UI> next to Porch.
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

export default function IOSGuide() {
  return (
    <Guide
      eyebrow="Porch pilot guide"
      title={
        <>
          Set up Porch on an <em>iPad</em>
        </>
      }
      lede={
        <p>
          This guide walks you through installing Porch on your loved one’s iPad, connecting the
          big-button phone and adding family members.
        </p>
      }
      aside={
        <>
          If your loved one uses an Android tablet, follow the{" "}
          <Link href="/pilot/android">Android setup guide</Link>. For family members’ phones, see the{" "}
          <Link href="/pilot/phone">phone guide</Link>.
        </>
      }
      kit={{
        intro:
          "I’ll send you the Porch phone adapter. Have the other parts ready before connecting the phone. Prices are approximate.",
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
