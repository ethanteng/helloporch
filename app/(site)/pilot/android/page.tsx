import Link from "next/link";
import { Chain, Contact, Email, Guide, guideMetadata, Questions, Says, Screenshot, Tip, UI, Warn, type GuidePart, type KitPart } from "../_guide/parts";
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
  { name: "An Android tablet", rule: "Android 15 or later", ...shopping.tablet, photo: "/pilot/ipad.jpg" },
  { name: "A big-button corded phone", rule: "Set to tone dialing", ...shopping.phone, photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the tablet", ...shopping.cell2jack, photo: "/pilot/cell2jack.jpg" },
  { name: "A USB-C hub", rule: "With a port for the tablet’s charger", ...shopping.hub, photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Optional", ...shopping.stand, photo: "/pilot/stand.jpg" },
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

// Where I suggest printing the phone's photo labels.
const fedExCopies = "https://www.office.fedex.com/default/copies.html";

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
        <li>
          <strong>Check the switch on the corded phone.</strong> Look on the side or bottom for <UI>T / P</UI> or{" "}
          <UI>Tone / Pulse</UI>. Set it to <UI>T</UI> or <UI>Tone</UI>.
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
          The same Porch app works on the tablet and on family members’ phones. Set up your loved one’s Porch on
          the tablet.
        </p>
        <Tip label="If the Play Store says the app isn’t available">
          <p>
            In Google Play, tap your profile picture and check the email address. If it’s different from the one you
            sent me, switch accounts or send me that address.
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
          On the tablet, tap the private setup link in your email or text. Porch opens to{" "}
          <UI>Who is this Porch for?</UI>
        </p>
        <p>If the link opens a HelloPorch web page, follow these steps.</p>
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
            Use the setup link on the tablet your loved one will use. You’ll add your own phone later with an
            invitation from the tablet.
          </p>
        </Warn>
      </>
    ),
  },
  {
    id: "setup",
    title: "Set up your loved one’s Porch",
    body: (
      <>
        <p>Where you see [Name] in this guide, the app shows the name you enter here.</p>
        <ol>
          <li>
            <strong>
              <UI>Who is this Porch for?</UI>
            </strong>{" "}
            Enter the name family members use, such as Grandpa Joe, and tap <UI>Continue</UI>. You can change it later.
          </li>
          <li>
            <strong>
              <UI>Choose a caregiver PIN</UI>
            </strong>{" "}
            Enter the same six digits twice. You’ll use this PIN to change settings on the tablet or your phone.
            Keep it somewhere safe.
          </li>
          <li>
            <strong>
              <UI>[Name]’s Porch number</UI>
            </strong>{" "}
            Tap <UI>Get number</UI> to get a phone number with the suggested area code. To pick another area code, tap{" "}
            <UI>Use a different area code</UI>. When the number appears, tap <UI>Continue</UI>.
          </li>
          <li>
            <strong>
              <UI>Microphone, camera and notifications</UI>
            </strong>{" "}
            Tap <UI>Continue</UI>. Allow notifications, and choose <UI>While using the app</UI> when asked about the
            microphone and camera.
          </li>
          <li>
            <strong>
              <UI>How will [Name] call?</UI>
            </strong>{" "}
            Choose <UI>Corded phone</UI>. If you’re waiting for a part, tap <UI>Do this later</UI> on the next screen.
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
        <p>
          When the tablet shows <UI>Add your phone</UI>, follow these steps to call, send messages and change Porch
          settings from your own phone.
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
            On the tablet, type your name as you want it to appear when you call. Tap <UI>Show QR code</UI>.
          </li>
          <li>
            Open the Camera app on your phone and point it at the square code on the tablet. Tap the link that
            appears, then tap <UI>Join family</UI> in Porch.
          </li>
          <li>
            The tablet says <Says>Your phone joined [Name]’s Porch.</Says> Tap <UI>Continue</UI>, then{" "}
            <UI>Back to the clock</UI>.
          </li>
        </ol>
        <p>If the link opens a web page, tap <UI>Open invitation in Porch</UI>. If Porch still doesn’t open, try either option below.</p>
        <ul>
          <li>
            Tap <UI>Copy invitation</UI>, open Porch, tap <UI>I’m joining my family</UI>, paste it into{" "}
            <UI>Invitation link</UI> and tap <UI>Join family</UI>.
          </li>
          <li>
            On the tablet, tap <UI>Send the invitation instead</UI> and send the link to your phone.
          </li>
        </ul>
        <Screenshot
          src="/pilot/screens/android-phone-home.png"
          width={675}
          height={1500}
          device="phone"
          alt="Porch on an Android phone after joining Rose’s Porch: Audio call, Video call, Send a message, Messages with Rose, Rose’s Porch number with Add to Contacts and Share this number, Your name and photo, and Leave this family."
          caption="Porch on your Android phone once you’ve joined."
        />
        <h3 id="ring">Let calls ring your Android phone</h3>
        <p>Look for these options at the top of the Porch app on your phone.</p>
        <ul>
          <li>
            Under <UI>Ring when Porch is closed</UI>, tap <UI>Allow</UI>. Allow notifications, microphone and camera access.
          </li>
          <li>
            Under <UI>Show calls on the lock screen</UI>, tap <UI>Open settings</UI> and allow full-screen notifications
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
          The tablet opens Porch when it restarts or when someone presses Home.
        </p>
        <Screenshot
          src="/pilot/screens/android-clock.png"
          width={1600}
          height={1000}
          device="tablet"
          alt="Porch’s clock on an Android tablet, with a gear in the top right corner, a Call someone button, and the link Make Porch this tablet’s home screen under it."
          caption="The home screen link is under Call someone. The gear in the top right corner opens caregiver mode."
        />
        <p>
          To reach Android’s own settings later, open caregiver mode, then <UI>This tablet</UI> and{" "}
          <UI>Tablet settings</UI>.
        </p>
      </>
    ),
  },
  {
    id: "keypad",
    title: "Set up the phone’s number keys",
    body: (
      <>
        <p>
          Set up keys 1 to 8 on the tablet, one person per key. Key 0 answers and hangs up. Key 9 turns the camera
          off and on during video calls.
        </p>
        <ol>
          <li>
            On the clock, tap the gear in the top right corner. Enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI>. The keypad is laid out like the phone’s. Tap a key, such as 1.
          </li>
          <li>
            Choose <UI>Call a person</UI> under the heading for that key, such as <UI>What key 1 does</UI>.
          </li>
          <li>
            Under <UI>Their details</UI>, tap <UI>Choose from Family on Porch</UI> for someone who has already joined.
            For anyone else, type their name or tap <UI>Choose from Contacts</UI>. To invite them, tap <UI>Invite them</UI>.
          </li>
          <li>
            Under <UI>Calls start as</UI>, choose video or audio. Add a photo under <UI>Photo &amp; button color</UI>.
          </li>
          <li>
            To try their regular phone if they miss a Porch call, turn on <UI>Call their phone</UI> and enter their{" "}
            <UI>Primary number</UI> under <UI>Phone</UI>. By default, Porch tries that number after 20 seconds.
            For numbers outside the US, start with + and the country code.
          </li>
          <li>
            Tap <UI>Save</UI>. Repeat for each key.
          </li>
        </ol>
        <Screenshot
          src="/pilot/screens/android-keypad.png"
          width={1600}
          height={1000}
          device="tablet"
          alt="Caregiver mode on an Android tablet with People open. The keypad shows David on key 1, Sarah on 2, Maria on 3 and James on 4, Video on / off on 9, Answer / hang up on 0, and Add on the empty keys."
          caption="People in caregiver mode. Tap Add on an empty key to set it up."
        />
        <p>
          Porch blocks calls from unknown numbers by default. To let a number through, open <UI>Calls</UI> in
          caregiver mode, then <UI>Blocked numbers</UI>, and tap <UI>Allow</UI> next to the number.
        </p>
      </>
    ),
  },
  {
    id: "labels",
    title: "Put photos on the phone’s keys",
    body: (
      <>
        <p>
          Use the <Link href="/labels">phone button label maker</Link> to print a name and photo for each key.
          You can use it on a computer, tablet or phone. The photos stay on that device.
        </p>
        <ol>
          <li>
            Under <UI>Choose your contacts</UI>, select the number of people you assigned to keys.
          </li>
          <li>
            Under <UI>Add names and photos</UI>, enter names in key order and tap <UI>Add photo</UI> for each person.
            Use a close-up of their face. Tap <UI>Preview &amp; adjust</UI> to move or zoom the photo.
          </li>
          <li>
            Measure the width and height of a button in inches, including the space for the name. Enter the measurements under{" "}
            <UI>Set the label size and quantity</UI>.
          </li>
          <li>
            Check the <UI>Print preview</UI>, then tap <UI>Download print-ready PDF</UI>.
          </li>
          <li>
            Print in color at <UI>Actual Size</UI> or 100% so the labels fit the keys.
          </li>
          <li>
            Cut out each label and match it to the key you assigned in <UI>People</UI>. If the keys have clear
            covers, lift them and slide the labels underneath.
          </li>
        </ol>
        <Tip label="Printing at a shop">
          <p>
            If you use a print shop such as <a href={fedExCopies}>FedEx Office</a>, ask for color on{" "}
            <strong>Matte Cover (100 lb.)</strong> paper at 100% size. Matte paper cuts down on glare under the key covers.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "family",
    title: "Invite family members",
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
            Enter their name. <UI>Audio drop-in</UI> and <UI>Video drop-in</UI> let their calls connect without your loved
            one answering. Turn off either option if you want their calls to ring. Turn on <UI>Caregiver mode</UI>{" "}
            for people who should be able to change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI>, then <UI>Share invitation</UI> and send it by text or email. If they’re next
            to you, they can scan the QR code.
          </li>
        </ol>
        <p>
          Each invitation works once and expires after 24 hours. The link shows them how to get Porch. Relatives with an Android
          phone need to be in the Google Play test first, so send me their Google account before you invite them.
          Relatives with an iPhone can install Porch through TestFlight.
        </p>
      </>
    ),
  },
  {
    id: "test",
    title: "Test calls in both directions",
    body: (
      <>
        <h3>Call your loved one from your phone</h3>
        <p>
          With the clock showing on the tablet, tap <UI>Video call</UI> in Porch on your phone.
        </p>
        <ul>
          <li>
            If you can drop in, the tablet announces the caller and connects after five seconds. Tap{" "}
            <UI>Don’t connect</UI> or press 0 to stop it.
          </li>
          <li>
            If you can’t drop in, the tablet rings. Your loved one can tap <UI>Answer video call</UI> or lift the
            receiver and press 0.
          </li>
        </ul>
        <h3>Call you from the tablet</h3>
        <p>
          Lift the receiver and press your key. The tablet says <Says>Calling</Says> and your name, and your
          phone rings. Put the receiver back to hang up.
        </p>
        <p>
          If you added a regular phone number to your key, Porch tries that number when you miss the call. Your
          phone’s voicemail can take a message. If you left the number blank, your loved one can leave a message in Porch.
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
            <strong>Make a call.</strong> Lift the receiver and press the person’s key. Or tap{" "}
            <UI>Call someone</UI> and choose their name.
          </li>
          <li>
            <strong>Answer a call.</strong> Lift the receiver and press 0, or tap the answer button.
          </li>
          <li>
            <strong>Hang up.</strong> Put the receiver back or press 0.
          </li>
          <li>
            <strong>Play a message.</strong> Tap <UI>Play 1 message</UI> on the clock screen.
          </li>
          <li>
            Family members can call and send messages from Porch on their phones. People you approve can also drop in.
          </li>
        </ul>
        <p>See <Link href="/pilot/features">Porch features and settings</Link> for calling, messages and caregiver settings.</p>
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
          then <UI>Display &amp; voice</UI>. Choose a <UI>Bedside language</UI> and tap <UI>Save</UI>.
        </p>
        <p>
          If Porch says no voice is available for that language, add one in Android’s <UI>Settings</UI>, under{" "}
          <UI>Accessibility</UI>, then <UI>Text-to-speech output</UI>.
        </p>
        <p>
          The <Link href="/pilot/features#language">language, voice and clock settings</Link> are in the features guide.
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
