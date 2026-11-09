import Link from "next/link";
import { Chain, Contact, Guide, guideMetadata, Questions, Says, Tip, UI, Warn, type GuidePart, type KitPart } from "../_guide/parts";

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
  { name: "A big-button corded phone", rule: "Set to tone dialing", photo: "/pilot/phone.jpg" },
  { name: "A Cell2Jack", rule: "Connects the phone to the adapter", photo: "/pilot/cell2jack.jpg" },
  { name: "The Porch phone adapter", rule: "I’ll send it, set up and tested", photo: "/pilot/adapter.jpg" },
  { name: "A USB-C hub", rule: "With a port for the iPad’s charger", photo: "/pilot/hub.jpg" },
  { name: "A sturdy stand", rule: "Optional", photo: "/pilot/stand.jpg" },
];

function GetPorch({ device }: { device: string }) {
  return (
    <ol>
      <li>
        On the {device}, install Apple’s free <a href={testFlightApp}>TestFlight app</a> from the App Store.
      </li>
      <li>
        {testFlight ? (
          <>
            On the same {device}, open <a href={testFlight}>Porch’s TestFlight link</a>.
          </>
        ) : (
          <>On the same {device}, open the TestFlight link I sent you.</>
        )}{" "}
        TestFlight opens. Tap <UI>Accept</UI>, then <UI>Install</UI>.
      </li>
    </ol>
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
          During the pilot, use Apple’s TestFlight app to install Porch.
        </p>
        <ul>
          <li>
            I’ll email or text you a <strong>private setup link</strong>. It works on one iPad and expires after 14 days.
          </li>
          <li>
            I’ll mail you the <strong>Porch phone adapter</strong> or bring it in person. You can set up the iPad now
            and connect the phone when the adapter arrives.
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
          <li>
            <strong>Check the switch on the corded phone.</strong> Look on the side or bottom for <UI>T / P</UI> or{" "}
            <UI>Tone / Pulse</UI>. Set it to <UI>T</UI> or <UI>Tone</UI>.
          </li>
        </ol>
        <Tip label="An older iPad?">
          <p>
            An iPad with a Lightning charging port needs a different adapter. If you’re unsure which port your iPad
            has, ask me before you buy a hub.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "install",
    title: "Install Porch on the iPad",
    body: (
      <>
        <GetPorch device="iPad" />
        <p>
          Look for <UI>Porch Family Calling</UI> in TestFlight and <UI>Porch</UI> on the Home Screen.
        </p>
      </>
    ),
  },
  {
    id: "setup-link",
    title: "Open your setup link on the iPad",
    body: (
      <>
        <p>
          On the iPad, tap the private setup link in your email or text. Porch opens to{" "}
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
            Use the setup link on the iPad your loved one will use. You’ll add your own phone later with an
            invitation from the iPad.
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
            Enter the same six digits twice. You’ll use this PIN to change settings on the iPad or your phone.
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
              <UI>Microphone and camera</UI>
            </strong>{" "}
            Tap <UI>Continue</UI> and allow access to the microphone and camera so family can hear and see your loved one.
          </li>
          <li>
            <strong>
              <UI>How will [Name] call?</UI>
            </strong>{" "}
            Choose <UI>Corded phone</UI>. If the adapter hasn’t arrived, tap <UI>Do this later</UI> on the next screen.
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
        <p>
          When the iPad shows <UI>Add your phone</UI>, follow these steps to call, send messages and change Porch
          settings from your own phone.
        </p>
        <ol>
          <li>
            <strong>Install Porch on your phone.</strong> On an iPhone, use TestFlight as you did on the iPad.
            If you use Android, send me the email address you use in Google Play. Once I’ve added you to the test,
            open the Google Play test link I send you on your phone. Join the test, then tap <UI>Install</UI> in Google Play.
          </li>
          <li>
            On the iPad, type your name as you want it to appear when you call. Tap <UI>Show QR code</UI>.
          </li>
          <li>
            Open the Camera app on your phone and point it at the square code on the iPad. Tap the link that appears,
            then tap <UI>Join family</UI> in Porch.
          </li>
          <li>
            On an iPhone, allow notifications so calls can ring and allow microphone access so people can hear you.
            On Android, follow the steps to <Link href="/pilot/android#ring">let calls ring your phone</Link>.
          </li>
          <li>
            The iPad says <Says>Your phone joined [Name]’s Porch.</Says> Tap <UI>Continue</UI>.
          </li>
        </ol>
        <Tip label="If the iPad keyboard doesn’t appear">
          <p>
            With the phone adapter plugged in, the iPad treats it as a keyboard and may hide its own. Tap{" "}
            <UI>Porch keyboard</UI> under the field, or unplug the adapter while you type.
          </p>
        </Tip>
        <p>If the link opens a web page, tap <UI>Open invitation in Porch</UI>. If Porch still doesn’t open, try either option below.</p>
        <ul>
          <li>
            Tap <UI>Copy invitation</UI>, open Porch, tap <UI>I’m joining my family</UI>, paste it into{" "}
            <UI>Porch invitation</UI> on iPhone or <UI>Invitation link</UI> on Android. Tap <UI>Join family</UI>.
          </li>
          <li>
            On the iPad, tap <UI>Send the invitation instead</UI> and send the link to your phone.
          </li>
        </ul>
        <h3>On your iPhone</h3>
        <ul>
          <li>
            Under <UI>[Name]’s Porch number</UI>, tap <UI>Add to Contacts</UI>, so you recognize their Porch when it calls you.
          </li>
          <li>
            Tap the person icon in the top right corner, then <UI>Add a photo</UI>. Your loved one sees it when you call. You can
            change your name there too.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: "keypad",
    title: "Set up the phone’s number keys",
    body: (
      <>
        <p>
          Set up keys 1 to 8 on the iPad, one person per key. Key 0 answers and hangs up. Key 9 turns the camera
          off and on during video calls.
        </p>
        <ol>
          <li>
            Setup ends on <UI>[Name]’s Porch is ready</UI>. Tap <UI>Put people on the keypad</UI>. Later, tap the gear on
            the clock, enter your PIN and tap <UI>Open caregiver mode</UI>.
          </li>
          <li>
            Open <UI>People</UI> and tap a key, such as 1.
          </li>
          <li>
            Choose <UI>Call a person</UI> under the heading for that key, such as <UI>What key 1 does</UI>.
          </li>
          <li>
            Under <UI>Their details</UI>, tap <UI>Choose from Family on Porch</UI> for someone who has already joined.
            For anyone else, type their name or tap <UI>Choose from Contacts</UI>. To invite them, tap <UI>Invite them</UI>.
          </li>
          <li>
            Under <UI>Calls start as</UI>, choose video or audio. Under <UI>Photo &amp; button color</UI>, tap <UI>Add photo</UI>.
          </li>
          <li>
            To try their regular phone if they miss a Porch call, turn on <UI>Call their phone</UI> and enter their{" "}
            <UI>Primary number</UI>. By default, Porch tries that number after 20 seconds. For numbers outside the US,
            start with + and the country code.
          </li>
          <li>
            Tap <UI>Save</UI>. Repeat for each key.
          </li>
        </ol>
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
        <p>Each relative gets their own invitation, from your iPhone:</p>
        <ol>
          <li>
            In Porch, tap the person icon in the top right corner, then <UI>Caregiver mode</UI>. Enter the PIN and tap{" "}
            <UI>Open caregiver mode</UI>.
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
            Tap <UI>Create invitation</UI> and send it by text or email. Then tap <UI>Done</UI>.
          </li>
        </ol>
        <p>
          Each invitation works once and expires after 24 hours. The link shows them how to get Porch. On an iPhone, that’s
          TestFlight and Porch, as you did. Relatives with an Android phone need me to add them to the Google Play test
          first, so send me their Google account before you invite them.
        </p>
        <p>
          You can also invite people from the iPad: in caregiver mode, open <UI>People</UI> and tap{" "}
          <UI>Invite someone</UI>.
        </p>
      </>
    ),
  },
  {
    id: "test",
    title: "Test calls in both directions",
    body: (
      <>
        <h3>Call your loved one from your iPhone</h3>
        <p>
          With the clock showing on the iPad, tap <UI>Video call</UI> in Porch on your iPhone. With drop-ins enabled,
          the iPad announces the caller and connects after five seconds. Tap <UI>Don’t connect</UI> or press 0 to stop it.
        </p>
        <p>
          If the caller can’t drop in, the iPad rings. Your loved one can tap <UI>Answer video call</UI> or lift the
          receiver and press 0.
        </p>
        <h3>Call you from the iPad</h3>
        <p>
          Lift the receiver and press your key. The iPad says <Says>Calling</Says> and your name, and your iPhone
          rings like a regular phone call, even when it’s locked. Put the receiver back to hang up.
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
            <strong>Answer a call.</strong> Lift the receiver and press 0, or tap the answer button. To decline, tap{" "}
            <UI>Decline</UI> on the screen.
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
          Porch can speak English, Mandarin, Cantonese, Spanish, Tagalog and Korean. On the iPad, open caregiver mode,
          then <UI>Display &amp; voice</UI>. Choose a <UI>Bedside language</UI> and tap <UI>Save</UI>.
        </p>
        <p>
          The <Link href="/pilot/features#language">language, voice and clock settings</Link> are in the features guide.
        </p>
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
