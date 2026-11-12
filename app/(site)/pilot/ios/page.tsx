import Link from "next/link";
import { Chain, Choices, Contact, FilmedVideo, Guide, guideMetadata, Links, Questions, Says, Screenshot, StepVideo, Tip, UI, type GuidePart, type KitPart } from "../_guide/parts";
import { qrFor, testFlight, testFlightApp } from "../links";
import { shopping } from "../shopping";

/** Filmed at home: plugging in the corded phone, Cell2Jack, Porch phone adapter and hub. */
const connectPhoneVideo =
  "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/How%20to%20connect%20phone%20to%20iPad%20compressed.mp4";

export const metadata = guideMetadata(
  "Set up Porch on an iPad | HelloPorch",
  "Set up your loved one’s iPad, connect the corded phone and add family members to Porch.",
);

const kit: KitPart[] = [
  { name: "An iPad", rule: "iPadOS 15 or later", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the iPad", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "The Porch phone adapter", rule: "Most iPads need this. I will mail it to you.", ...shopping.adapter, photo: "/pilot/adapter.jpg" },
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
          During the pilot, Porch is a test app that comes through Apple’s TestFlight app. Open these on your loved
          one’s iPad, in this order.
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
                  Install this first. Tap <UI>Get</UI> to install Apple’s free TestFlight app. You don’t need to open it.
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
              how: "It works on one iPad and expires after 14 days.",
            },
          ]}
        />
        <p>
          You’ll also add Porch to your own phone partway through. The <Link href="/pilot/phone">phone guide</Link>{" "}
          covers phones, for you and the rest of the family.
        </p>
        <p>
          Most iPads need the <strong>Porch phone adapter</strong> between the Cell2Jack and the hub. I’ll mail it to
          you. Or, if you are in the Bay Area, I can bring it to you in-person. You can set up the iPad now and connect
          the phone when the adapter arrives.
        </p>
        <p>
          An iPad Pro from 2021 or later or an iPad Air from 2022 or later doesn’t need it. Porch’s setup calls these
          iPads with an M chip. The standard iPad and the iPad mini always need the adapter. To see which iPad it is,
          open <UI>Settings</UI>, then <UI>General</UI> and <UI>About</UI>. Send me what it says under{" "}
          <UI>Model Name</UI> and I’ll tell you.
        </p>
        <Tip>
          <p>
            Allow about 30 minutes. Have the iPad, corded phone, Cell2Jack and your own phone nearby, and the adapter
            if the iPad needs one.
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
            <strong>Check the date and time are set automatically,</strong> under <UI>Settings</UI>, <UI>General</UI>,{" "}
            <UI>Date &amp; Time</UI>.
          </li>
          <li>
            <strong>Sign in to the App Store</strong> with an Apple ID, so the iPad can install TestFlight.
          </li>
          <li>
            <strong>Make sure you can open your setup link on it,</strong> from your email or texts on the iPad, or by
            AirDrop from your iPhone.
          </li>
        </ol>
        <Tip label="An older iPad?">
          <p>
            An iPad with a Lightning charging port needs a Lightning hub with a port for the charger instead of a
            USB-C hub, such as{" "}
            <a href={shopping.lightningHub.href} target="_blank" rel="noopener noreferrer">
              this one on Amazon
            </a>{" "}
            ({shopping.lightningHub.price.toLowerCase()}). If you’re unsure which port your iPad has, ask me
            before you buy a hub.
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
          caption="Installing Porch, opening your setup link and setting up your loved one’s Porch."
        />
        <ol>
          <li>
            On the iPad, install Apple’s free <a href={testFlightApp}>TestFlight app</a>. Then open{" "}
            <a href={testFlight}>Porch’s TestFlight link</a> and tap{" "}
            <UI>Accept</UI>, then <UI>Install</UI>. Porch appears on the Home Screen.
          </li>
          <li>
            Tap your private setup link on the iPad your loved one will use. Porch opens and asks{" "}
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
            Tap <UI>Continue</UI> and allow the microphone and camera.
          </li>
          <li>
            Choose <UI>Corded phone</UI>. If the iPad needs the phone adapter and it hasn’t arrived yet, tap{" "}
            <UI>Do this later</UI>.
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
          make and answer calls. You’ll see and hear the caller on the iPad and speak into the iPad’s microphone.
        </p>
        <p>How you plug the phone in depends on whether the iPad needs the adapter.</p>
        <h3>Most iPads, with the adapter</h3>
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
            <strong>Plug the iPad’s charger into the hub first,</strong> and the hub into the iPad. The charger powers
            the adapter and the Cell2Jack as well as the iPad.
          </li>
          <li>Plug the phone’s cord into the Cell2Jack, and the Cell2Jack’s USB cable into the adapter.</li>
          <li>
            Plug the adapter’s USB-C cable into the hub. The adapter’s red light blinks, then stays on. That takes a few
            seconds.
          </li>
        </ol>
        <h3>iPad Pro (2021 or later) and iPad Air (2022 or later)</h3>
        <Chain label="How it connects without the adapter" items={["Corded phone", "Cell2Jack", "USB-C hub", "iPad"]} />
        <ol>
          <li>
            <strong>Plug the iPad’s charger into the hub first,</strong> and the hub into the iPad. The charger powers
            the Cell2Jack as well as the iPad.
          </li>
          <li>Plug the phone’s cord into the Cell2Jack, and the Cell2Jack’s USB cable into the hub.</li>
          <li>
            On the <UI>Connect the phone</UI> screen, tap <UI>Open Settings</UI>. Turn on{" "}
            <UI>Cell2Jack USB Driver</UI>, then go back to Porch.
          </li>
          <li>
            Unplug the Cell2Jack from the hub for ten seconds and plug it back in. Porch shows{" "}
            <UI>The phone is connected.</UI>
          </li>
        </ol>
        <h3>Then test the phone</h3>
        <ol>
          <li>
            When Porch asks, lift the receiver and press a key, such as 3. Listen for{" "}
            <Says>Porch heard 3. Now put the receiver back.</Says> This is a test.
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
          alt="The Connect the phone screen on an iPad, with three numbered steps and the message: Porch heard 3. Now put the receiver back."
          caption="The phone check after pressing 3. Hang up next."
        />
        <Tip label="If the phone keys don’t respond">
          <ul>
            <li>Check the hub’s charger is plugged in, so the iPad can power the Cell2Jack, and the adapter if it has one.</li>
            <li>
              If the adapter’s light keeps blinking, unplug the Cell2Jack from it for ten seconds and plug it back in.
            </li>
            <li>If the adapter’s light never comes on, try another USB-C cable. Some cables only charge.</li>
            <li>
              Without the adapter, the Cell2Jack works only on an iPad Pro from 2021 or later or an iPad Air from 2022
              or later, with iPadOS 16 or later. Tap <UI>Open Settings</UI> and check that <UI>Cell2Jack USB Driver</UI> is on. Then unplug the Cell2Jack for
              ten seconds and plug it back in.
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
            <strong>On your phone:</strong> allow what Porch asks for, so calls can ring. See{" "}
            <Link href="/pilot/phone#ring">Let calls ring your phone</Link>.
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
            Enter their name. If they’re already on the keypad, use the name on their key, so their key switches to
            their Porch app when they join. Turn off <UI>Audio drop-in</UI> or <UI>Video drop-in</UI> if their calls
            should ring first. Turn on <UI>Caregiver mode</UI> for people who should change settings.
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
            You can invite someone whenever they’re ready, from your phone as above, or on the iPad: open caregiver
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
    body: (
      <>
        <StepVideo
          name="ios-keypad"
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
            When setup ends, tap <UI>Put people on the keypad</UI>. Later, tap the gear on the clock, enter your PIN
            and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI> and tap the key you want to set up, such as 1. To have it call someone, choose{" "}
            <UI>Call a person</UI>.
          </li>
          <li>
            If they’ve joined, tap <UI>Choose from Family on Porch</UI> and choose them. For anyone else, type their
            name or tap <UI>Choose from Contacts</UI>. If you’ve invited them, use the name on their invitation.
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
        <h3>When someone joins Porch later</h3>
        <p>
          A key can start with someone’s regular phone number and switch to their Porch app once they join. It switches
          on its own when their invitation has the same name as their key, such as Sarah on key 1 and an invitation for
          Sarah. Capital letters and extra spaces don’t matter, and it works however you invite them: from your phone,
          from <UI>People</UI>, or with <UI>Invite</UI> on their key’s page. Their phone number stays as the one Porch
          tries when they miss a call.
        </p>
        <p>
          If their key doesn’t switch, such as when their invitation has another name or two keys share their name,
          switch it yourself. In <UI>People</UI>, tap their key, then <UI>Choose from Family on Porch</UI> and choose
          them.
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
          Porch starts in English. You only need this step if your loved one is more comfortable in another
          language. Once you switch, the iPad shows and speaks that language. Caregiver mode and family phones stay
          in English.
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
          label="Video: changing the bedside language and voice"
          caption="Switching the bedside to Spanish and choosing a voice."
        />
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>Display &amp; voice</UI>. Under <UI>Bedside language</UI>, choose your loved one’s language.
          </li>
          <li>
            To pick a voice, use the menu under <UI>Announcement voice</UI>. <UI>Preview announcement</UI> lets you
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
          For more on any feature or setting, see the <Link href="/pilot/features">features guide</Link>.
        </p>
        <Questions
          items={[
            {
              q: "The phone’s keys don’t do anything.",
              a: (
                <p>
                  Lift the receiver before pressing a key, and check that the charger is plugged into the hub. If the
                  iPad uses the adapter, check that its red light is on. Then open caregiver mode, <UI>This iPad</UI>,
                  and run <UI>Connect the phone</UI> again. Without the adapter, tap <UI>Open Settings</UI> there and
                  check that <UI>Cell2Jack USB Driver</UI> is on.
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
                  The <Link href="/pilot/features">features guide</Link> may have your answer. If not, tell me what
                  happened and which device you were using. You can <Contact />. If there’s an error on the screen, a
                  photo helps.
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
          Set up the iPad your loved one will use, connect their big-button phone and add Porch to your own phone.
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
          "Most iPads need the Porch phone adapter, which I’ll send you. Have the other parts ready before you connect the phone. Prices are approximate.",
        parts: kit,
        ready: [
          "Wi-Fi where your loved one lives, and its password.",
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
