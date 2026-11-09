import Link from "next/link";
import { Chain, Contact, Guide, guideMetadata, Questions, Says, Screenshot, StepVideo, Tip, UI, type GuidePart, type KitPart } from "../_guide/parts";
import { shopping } from "../shopping";

export const metadata = guideMetadata(
  "Set up Porch on an iPad | HelloPorch",
  "Set up your loved one’s iPad, connect the corded phone and add family members to Porch.",
);

// Porch's public TestFlight link, the same one invitation pages use. Without it, the guide says I'll send it.
const testFlight = process.env.NEXT_PUBLIC_TESTFLIGHT_URL;
// Apple's TestFlight app on the App Store.
const testFlightApp = "https://apps.apple.com/app/testflight/id899247664";

const kit: KitPart[] = [
  { name: "An iPad", rule: "iPadOS 15 or later", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", rule: "Set to tone dialing", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the adapter", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "The Porch phone adapter", rule: "Custom component", ...shopping.adapter, photo: "/pilot/adapter.jpg" },
  { name: "A USB-C hub", rule: "With a port for the iPad’s charger", ...shopping.hub, photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Optional", ...shopping.stand, photo: "/pilot/stand.jpg" },
];

const parts: GuidePart[] = [
  {
    id: "before",
    title: "Before you start",
    body: (
      <>
        <p>
          During the pilot, use Apple’s TestFlight app to install Porch.
        </p>
        <ul>
          <li>
            I’ll email or text you a <strong>private setup link</strong>. It works on one iPad and expires after 14 days.
          </li>
          <li>
            I’ll mail you the <strong>Porch phone adapter.</strong> Or, if you are in the Bay Area, I can bring it to
            you in-person. You can set up the iPad now and connect the phone when the adapter arrives.
          </li>
        </ul>
        <Tip>
          <p>Allow about 30 minutes. Have the iPad, corded phone, adapter and your own phone nearby.</p>
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
            {testFlight ? <a href={testFlight}>Porch’s TestFlight link</a> : "the TestFlight link I sent you"} and tap{" "}
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
            Choose <UI>Corded phone</UI>. If the phone adapter hasn’t arrived yet, tap <UI>Do this later</UI>.
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
        <Chain label="How it connects" items={["Corded phone", "Cell2Jack", "Porch phone adapter", "USB-C hub", "iPad"]} />
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
            <li>Check the hub’s charger is plugged in, so the iPad can power the adapter and the Cell2Jack.</li>
            <li>
              If the adapter’s light keeps blinking, unplug the Cell2Jack from it for ten seconds and plug it back in.
            </li>
            <li>If the light never comes on, try another USB-C cable. Some cables only charge.</li>
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
            If you have an iPhone, install TestFlight first, then install Porch as you did on the iPad. On an Android
            phone, send me the email address you use in Google Play, and I’ll send you a test link.
          </li>
          <li>
            On the iPad, type your name, then tap <UI>Show QR code</UI>.
          </li>
          <li>Open the Camera app on your phone and point it at the code. Tap the link that appears.</li>
          <li>
            Porch opens on your phone. Tap <UI>Join family</UI>.
          </li>
          <li>
            On an iPhone, allow the microphone and notifications, so calls can ring. On Android,{" "}
            <Link href="/pilot/android#ring">let calls ring your phone</Link>.
          </li>
          <li>
            The iPad says your phone joined. Tap <UI>Continue</UI>.
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
          name="ios-invite"
          label="Video: inviting a relative from your phone"
          caption="Inviting a relative from your iPhone."
        />
        <ol>
          <li>
            In Porch on your iPhone, tap the person icon in the top right corner, then <UI>Caregiver mode</UI>. Enter
            the PIN and tap <UI>Open caregiver mode</UI>.
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
        <p>
          Each invitation works once and expires after 24 hours. Relatives with an Android phone need me to add them to
          the Google Play test first, so send me their Google account before you invite them.
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
          name="ios-language"
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
      <Questions
        items={[
          {
            q: "The phone’s keys don’t do anything.",
            a: (
              <p>
                Lift the receiver before pressing a key. Check that the adapter’s red light is on and the charger
                is plugged into the hub. Then open caregiver mode, <UI>This iPad</UI>, and run{" "}
                <UI>Connect the phone</UI> again.
              </p>
            ),
          },
          {
            q: "My iPhone doesn’t ring when my loved one calls.",
            a: (
              <p>
                Check that Porch’s notifications and microphone are allowed in your iPhone’s Settings, under Porch. A
                Focus or Do Not Disturb can silence Porch calls, and so can the Ring/Silent switch.
              </p>
            ),
          },
          {
            q: "My iPhone says Porch isn’t ready.",
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
            q: "My phone won’t join from the QR code.",
            a: (
              <p>
                If the link opens a web page, tap <UI>Open invitation in Porch</UI>. Or tap <UI>Copy invitation</UI>,
                open Porch, tap <UI>I’m joining my family</UI>, paste it in and tap <UI>Join family</UI>. You can also
                tap <UI>Send the invitation instead</UI> on the iPad and send the link to your phone.
              </p>
            ),
          },
          {
            q: "An invitation or the setup link stopped working.",
            a: (
              <p>
                Family invitations work once and expire after 24 hours. Create a new invitation in caregiver mode. If the
                setup link for the iPad has expired, ask me for a new one.
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
            q: "Porch won’t open, or says it has expired.",
            a: (
              <p>
                Each test version lasts 90 days. Open TestFlight and tap <UI>Update</UI> next to Porch.
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
          <Link href="/pilot/android">Android setup guide</Link>.
        </>
      }
      kit={{
        intro: "I’ll send you the Porch phone adapter. Have the other parts ready before you connect the phone.",
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
