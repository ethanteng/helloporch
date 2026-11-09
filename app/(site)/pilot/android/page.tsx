import Link from "next/link";
import { Chain, Contact, Email, Guide, guideMetadata, Questions, Says, Tip, UI, Warn, type GuidePart, type KitPart } from "../_guide/parts";

export const metadata = guideMetadata(
  "Get started with Porch on Android | HelloPorch",
  "How to install Porch on an Android tablet and Android phones, set it up for your loved one, and connect the big-button phone.",
);

// Porch's Google Play testing page, the same one invitation pages use. Until it's set, the guide says I'll send it.
const playTesting = process.env.NEXT_PUBLIC_PLAY_TESTING_URL;
// For a caregiver with an iPhone: Porch's public TestFlight link, and Apple's TestFlight app.
const testFlight = process.env.NEXT_PUBLIC_TESTFLIGHT_URL;
const testFlightApp = "https://apps.apple.com/app/testflight/id899247664";

const kit: KitPart[] = [
  { name: "An Android tablet", rule: "Android 15 or later", photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", rule: "Set to tone dialing", photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the tablet", photo: "/pilot/cell2jack.jpg" },
  { name: "A USB-C hub", rule: "With a port for the tablet’s charger", photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Optional", photo: "/pilot/stand.jpg" },
];

function GetPorch({ device }: { device: string }) {
  return playTesting ? (
    <p>
      On the {device}, open <a href={playTesting}>Porch’s Google Play test</a>. Accept the invitation to test Porch,
      then follow the link to Google Play and tap <UI>Install</UI>.
    </p>
  ) : (
    <p>
      On the {device}, open the Google Play test link I sent you. Accept the invitation to test Porch, then follow the
      link to Google Play and tap <UI>Install</UI>.
    </p>
  );
}

const parts: GuidePart[] = [
  {
    id: "before",
    title: "Before you start",
    body: (
      <>
        <p>
          Porch isn’t in the Play Store for everyone yet. During the pilot, it comes through Google Play’s testing
          program, which only lets in the Google accounts I add.
        </p>
        <ol>
          <li>
            <strong>Email me the Google account</strong> (usually a Gmail address) that’s signed in to Google Play on the
            tablet, and the one on your own phone, at <Email />. Do the same later for any relative with an Android
            phone.
          </li>
          <li>
            <strong>I’ll send you two links.</strong> One lets you join Porch’s test on Google Play. The other is your
            private setup link, which sets up one tablet and lasts 14 days.
          </li>
        </ol>
        <Tip>
          <p>Set aside about 30 minutes, with the tablet, the phone and your own phone all within reach.</p>
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
          <strong>Charge it and connect it to Wi-Fi.</strong> Use the Wi-Fi where your loved one lives, if you can.
        </li>
        <li>
          <strong>Check the Android version.</strong> Open <UI>Settings</UI>, then <UI>About tablet</UI>. Porch needs
          Android 15 or later. Install any system update the tablet offers.
        </li>
        <li>
          <strong>Sign in to Google Play</strong> with the Google account you sent me.
        </li>
        <li>
          <strong>Set the phone to tone dialing.</strong> Most big-button phones have a switch on the side or bottom
          marked <UI>T / P</UI> or <UI>Tone / Pulse</UI>. Set it to <UI>T</UI>. Porch can’t hear pulse dialing.
        </li>
      </ol>
    ),
  },
  {
    id: "install",
    title: "Install Porch on the tablet",
    body: (
      <>
        <GetPorch device="tablet" />
        <p>
          It’s the same Porch app for the tablet and for phones. Porch knows a tablet from a phone by its screen size,
          so only a tablet can be set up for your loved one.
        </p>
        <Tip label="If the Play Store says the app isn’t available">
          <p>
            The tablet is probably signed in to a different Google account from the one you sent me. Check which
            account Google Play is using, or send me that one instead.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "setup-link",
    title: "Open your setup link on the tablet",
    body: (
      <>
        <p>
          On the tablet, open the email or text with your private setup link and tap it. It opens Porch straight to{" "}
          <UI>Who is this Porch for?</UI>
        </p>
        <p>If it opens a HelloPorch web page instead:</p>
        <ol>
          <li>
            Tap <UI>Open setup in Porch</UI>.
          </li>
          <li>
            If that doesn’t work, tap <UI>Copy setup link</UI>. Open Porch, tap <UI>Set up Porch for someone</UI>, paste
            the link into <UI>Setup link</UI> and tap <UI>Continue</UI>.
          </li>
        </ol>
        <Warn>
          <p>
            Open the setup link on the tablet that will stay with your loved one, not on your phone. On a phone, Porch
            only explains that the link is for the tablet.
          </p>
        </Warn>
      </>
    ),
  },
  {
    id: "setup",
    title: "Set up Porch, one screen at a time",
    body: (
      <>
        <p>Porch shows the name you choose on its screens. Below, we write it as [Name].</p>
        <ol>
          <li>
            <strong>
              <UI>Who is this Porch for?</UI>
            </strong>{" "}
            Type what the family calls them, such as Grandpa Joe or Aunt Linda. Family see this name, and you can change it
            later. Tap <UI>Continue</UI>.
          </li>
          <li>
            <strong>
              <UI>Choose a caregiver PIN</UI>
            </strong>{" "}
            Six digits, entered twice. You’ll use it to change Porch’s settings, on the tablet and from your phone.{" "}
            <strong>Write it down somewhere safe.</strong>
          </li>
          <li>
            <strong>
              <UI>[Name]’s Porch number</UI>
            </strong>{" "}
            Every Porch gets its own phone number, so people can call your loved one from any phone. Porch suggests an area code
            near the tablet. Tap <UI>Get number</UI>, or <UI>Use a different area code</UI> to pick another. It can
            take a little while. When the number appears, tap <UI>Continue</UI>.
          </li>
          <li>
            <strong>
              <UI>Microphone, camera and notifications</UI>
            </strong>{" "}
            Tap <UI>Continue</UI>. Android then asks three times. Allow each one. For the microphone and camera,
            choose <UI>While using the app</UI>.
          </li>
          <li>
            <strong>
              <UI>How will [Name] call?</UI>
            </strong>{" "}
            Choose <UI>Corded phone</UI>. The next part walks through it.
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
          Porch shows <UI>Connect the phone</UI>. Plug everything in this way, with the tablet’s charger in the hub so
          the tablet charges while the phone is connected:
        </p>
        <Chain label="How it connects" items={["Corded phone", "Cell2Jack", "USB-C hub", "Tablet"]} />
        <ol>
          <li>Plug the phone’s cord into the Cell2Jack, and the Cell2Jack’s USB cable into the hub.</li>
          <li>Plug the hub into the tablet, and the tablet’s charger into the hub’s charging port.</li>
          <li>
            Android asks whether to let Porch use the Cell2Jack. Tick the box to <strong>always open Porch</strong> for
            it, then tap <UI>OK</UI>. If you miss it, tap <UI>Allow Porch to use the Cell2Jack</UI>.
          </li>
          <li>
            Porch says <Says>The phone is connected. Lift the receiver and press a key.</Says> Do that, and Porch
            answers <Says>Porch heard 5. Now put the receiver back.</Says>
          </li>
          <li>
            Hang up. Porch says <Says>Porch heard you hang up. The phone is ready.</Says> Tap <UI>Continue</UI>.
          </li>
        </ol>
        <Tip label="Not working?">
          <ul>
            <li>Unplug the Cell2Jack and plug it back in. When Android asks, choose to always open Porch.</li>
            <li>Check the phone is set to tone dialing.</li>
            <li>The keys only work while the receiver is lifted.</li>
            <li>
              If the Cell2Jack announces the phone isn’t connected when you lift the receiver, press a key and it stops.
            </li>
          </ul>
        </Tip>
        <p>
          Waiting on a part? Tap <UI>Do this later</UI>. Your loved one can use the touchscreen meanwhile. Connect the phone any
          time from caregiver mode: <UI>This tablet</UI>, then <UI>Connect the phone</UI>.
        </p>
      </>
    ),
  },
  {
    id: "your-phone",
    title: "Add your phone",
    body: (
      <>
        <p>
          The tablet now shows <UI>Add your phone</UI>. Your phone becomes the caregiver’s phone: you can call your loved one, send
          messages and change settings from it.
        </p>
        <ol>
          <li>
            <strong>Install Porch on your phone first.</strong> On an Android phone, join the test and install Porch
            the same way you did on the tablet. On an iPhone, install Apple’s{" "}
            <a href={testFlightApp}>TestFlight app</a>, then open{" "}
            {testFlight ? <a href={testFlight}>Porch’s TestFlight link</a> : "the TestFlight link I sent you"} and tap{" "}
            <UI>Accept</UI>, then <UI>Install</UI>.
          </li>
          <li>
            On the tablet, type your name and tap <UI>Show QR code</UI>. Your name is how Porch tells your loved one who’s
            calling.
          </li>
          <li>
            Point your phone’s camera at the code and tap the link that appears. Porch opens with the invitation filled
            in. Tap <UI>Join family</UI>.
          </li>
          <li>
            The tablet says <Says>Your phone joined [Name]’s Porch.</Says> Tap <UI>Continue</UI>, then{" "}
            <UI>Back to the clock</UI>.
          </li>
        </ol>
        <p>If the link opens a web page instead of Porch, tap <UI>Open invitation in Porch</UI>. If that doesn’t work:</p>
        <ul>
          <li>
            Tap <UI>Copy invitation</UI>, open Porch, tap <UI>I’m joining my family</UI>, paste it into{" "}
            <UI>Invitation link</UI> and tap <UI>Join family</UI>.
          </li>
          <li>
            Or, on the tablet, tap <UI>Send the invitation instead</UI> and send it to yourself.
          </li>
        </ul>
        <h3>Let calls ring your phone</h3>
        <p>Porch’s home screen on your phone shows a card or two at the top. Follow each one:</p>
        <ul>
          <li>
            <UI>Ring when Porch is closed</UI>: tap <UI>Allow</UI> and allow notifications, the microphone and the
            camera.
          </li>
          <li>
            <UI>Show calls on the lock screen</UI>: tap <UI>Open settings</UI> and turn on full-screen notifications
            for Porch.
          </li>
        </ul>
        <p>
          While you’re there, tap <UI>Your name and photo</UI>, then <UI>Add a photo</UI>. Your loved one sees it when you call.
        </p>
      </>
    ),
  },
  {
    id: "home",
    title: "Make Porch the tablet’s home screen",
    body: (
      <>
        <p>
          On the tablet’s clock, tap <UI>Make Porch this tablet’s home screen</UI>, choose <UI>Porch</UI> and confirm.
          The tablet then always comes back to Porch, after a restart or if someone presses Home.
        </p>
        <p>
          To reach Android’s own settings later, open caregiver mode, then <UI>This tablet</UI> and{" "}
          <UI>Tablet settings</UI>.
        </p>
      </>
    ),
  },
  {
    id: "keypad",
    title: "Put people on the keypad",
    body: (
      <>
        <p>
          Each number key on the phone can call one person. Your loved one lifts the receiver and presses that person’s key. Set the keys
          up on the tablet:
        </p>
        <ol>
          <li>
            On the clock, tap <UI>Caregiver mode</UI> in the top right corner. Enter your PIN and tap{" "}
            <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI>. The keypad is laid out like the phone’s. Tap a key, such as 1.
          </li>
          <li>
            Under <UI>What key 1 does</UI>, choose <UI>Call a person</UI>.
          </li>
          <li>
            Under <UI>Their details</UI>:
            <ul>
              <li>
                For someone who has joined your loved one’s Porch, tap <UI>Choose from Family on Porch</UI>.
              </li>
              <li>
                Otherwise type their name, or tap <UI>Choose from Contacts</UI>. You can tap <UI>Invite them</UI> to
                send them an invitation.
              </li>
            </ul>
          </li>
          <li>
            Choose whether their calls start as video or audio, and add a photo under <UI>Photo &amp; button color</UI>.
          </li>
          <li>
            Under <UI>Phone</UI>, turn on <UI>Call their phone</UI> and enter their <UI>Primary number</UI>. If Porch
            isn’t answered in 20 seconds, Porch rings that number instead, voice only. Start numbers outside the US with
            +.
          </li>
          <li>
            Tap <UI>Save</UI>. Repeat for each key.
          </li>
        </ol>
        <Tip>
          <p>
            Keys 0 and 9 control calls: 0 answers and hangs up, and 9 turns video on and off. Use 1 to 8 for people.
            Many big-button phones have room for a photo on each key, which makes them easier for your loved one to find.
          </p>
        </Tip>
        <p>
          Only people on the keypad, and numbers you allow, can call your loved one’s Porch number from a regular phone. Anyone
          else is turned away and listed under <UI>Blocked numbers</UI>, where you can allow them.
        </p>
      </>
    ),
  },
  {
    id: "family",
    title: "Invite the rest of the family",
    body: (
      <>
        <p>Each relative gets their own invitation, from your phone:</p>
        <ol>
          <li>
            In Porch on your phone, tap <UI>Caregiver mode</UI>, enter the PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>Family</UI> and tap <UI>Invite someone</UI>.
          </li>
          <li>
            Type their name. Leave <UI>Audio drop-in</UI> and <UI>Video drop-in</UI> on if they may drop in without your loved
            one having to answer. Turn on <UI>Caregiver mode</UI> only for someone who should change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI>, then <UI>Share invitation</UI> and send it by text or email. If they’re next
            to you, they can scan the QR code.
          </li>
        </ol>
        <p>
          An invitation works once, within 24 hours. The link shows them how to get Porch. Relatives with an Android
          phone need to be in the Google Play test first, so send me their Google account before you invite them.
          Relatives with an iPhone can install it straight away.
        </p>
      </>
    ),
  },
  {
    id: "test",
    title: "Make a test call",
    body: (
      <>
        <h3>Call your loved one from your phone</h3>
        <p>
          In Porch on your phone, tap <UI>Video call</UI>. What happens on the tablet depends on whether you may drop
          in:
        </p>
        <ul>
          <li>
            <strong>Drop-in:</strong> the tablet says who’s dropping in and connects after five seconds. Your loved one can press 0
            or tap <UI>Don’t connect</UI> to stop it.
          </li>
          <li>
            <strong>A ringing call:</strong> the tablet shows <UI>Incoming video call</UI>. Tap{" "}
            <UI>Answer video call</UI>, or press 0 on the phone. Lifting the receiver alone doesn’t answer.
          </li>
        </ul>
        <h3>Call you from the tablet</h3>
        <p>
          Lift the receiver and press your key. The tablet says <Says>Calling</Says> and your name, and your
          phone rings. Put the receiver back to hang up.
        </p>
        <p>
          If you don’t answer, Porch rings your regular phone number, if you added one. If nobody answers, your loved one can leave
          you a message.
        </p>
      </>
    ),
  },
  {
    id: "everyday",
    title: "How your loved one uses Porch",
    body: (
      <>
        <ul>
          <li>
            <strong>To call someone,</strong> lift the receiver and press their key. Or tap <UI>Call someone</UI> on the
            screen.
          </li>
          <li>
            <strong>To answer,</strong> press 0 on the phone, or tap the answer button.
          </li>
          <li>
            <strong>To hang up,</strong> put the receiver back, or press 0.
          </li>
          <li>
            <strong>Messages</strong> from family wait on the tablet. The clock shows <UI>Play 1 message</UI> until your
            loved one plays it.
          </li>
          <li>
            <strong>Family</strong> can call, drop in if you allowed it, and send video or voice messages from their
            phones.
          </li>
        </ul>
        <p>
          For every feature, what it does out of the box and how to change it, see{" "}
          <Link href="/pilot/features">Every Porch feature</Link>.
        </p>
      </>
    ),
  },
  {
    id: "language",
    title: "Change the language or voice",
    body: (
      <>
        <p>
          Porch can speak English, Mandarin, Cantonese, Spanish, Tagalog and Korean. On the tablet, open caregiver mode,
          then <UI>Display &amp; voice</UI>, and choose under <UI>Bedside language</UI>. Tap <UI>Save</UI>.
        </p>
        <p>
          If Porch says no voice is available for that language, add one in Android’s <UI>Settings</UI>, under{" "}
          <UI>Accessibility</UI>, then <UI>Text-to-speech output</UI>.
        </p>
      </>
    ),
  },
  {
    id: "settings",
    title: "Tablet settings that help",
    body: (
      <ul>
        <li>
          <strong>Keep it plugged in,</strong> with the charger in the hub. Porch keeps the screen on while it’s the
          bedside.
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
                Lift the receiver first: the keys only work while it’s off the cradle. Check the phone is set to tone
                dialing. Then open caregiver mode, <UI>This tablet</UI>, and run <UI>Connect the phone</UI> again, or tap{" "}
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
                The tablet is off, out of charge, off Wi-Fi, or Porch isn’t open. Check it’s plugged in and connected
                to Wi-Fi, and that Porch is showing the clock.
              </p>
            ),
          },
          {
            q: "An invitation or the setup link stopped working.",
            a: (
              <p>
                Invitations for relatives last 24 hours and work once. Make a new one from caregiver mode. If your
                setup link has run out, ask me for a new one.
              </p>
            ),
          },
          {
            q: "Someone can’t call my loved one’s Porch number.",
            a: (
              <p>
                Unknown callers are turned away. Put them on the keypad with their number, or allow them from{" "}
                <UI>Blocked numbers</UI> in caregiver mode.
              </p>
            ),
          },
          {
            q: "Something else.",
            a: (
              <p>
                Tell me what happened. You can <Contact />. A photo of the screen helps. This is a pilot, and I
                want to hear about anything that’s confusing.
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
          Get started on <em>Android.</em>
        </>
      }
      lede={
        <p>
          Everything you need to set up Porch on your loved one’s Android tablet, connect their big-button phone, and
          get the family calling from their own phones.
        </p>
      }
      aside={<>Using the other kind? <Link href="/pilot/ios">The iPad and iPhone guide</Link></>}
      kit={{
        intro: "Android tablets read the phone through the Cell2Jack directly, so there’s no adapter to wait for.",
        parts: kit,
        ready: [
          "Wi-Fi where your loved one lives, and its password.",
          "Your private setup link, and the link to join Porch’s Google Play test. I’ll send you both.",
          "Your own phone, iPhone or Android, to pair as the caregiver’s phone.",
          "A few photos of the people your loved one calls most, for their keys.",
        ],
      }}
      parts={parts}
    />
  );
}
