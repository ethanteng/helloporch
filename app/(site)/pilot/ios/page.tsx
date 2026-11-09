import Link from "next/link";
import { Chain, Contact, Guide, guideMetadata, Questions, Says, Tip, UI, Warn, type GuidePart, type KitPart } from "../_guide/parts";

export const metadata = guideMetadata(
  "Get started with Porch on iPad and iPhone | HelloPorch",
  "How to install Porch on an iPad and iPhones, set it up for your loved one, and connect the big-button phone through the Porch phone adapter.",
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
        On the {device}, install Apple’s <a href={testFlightApp}>TestFlight app</a> from the App Store. It’s free, and
        it’s how Apple lets people try apps before they’re in the App Store.
      </li>
      <li>
        {testFlight ? (
          <>
            Still on the {device}, open <a href={testFlight}>Porch’s TestFlight link</a>.
          </>
        ) : (
          <>Still on the {device}, open the TestFlight link I sent you.</>
        )}{" "}
        TestFlight opens. Tap <UI>Accept</UI>, then <UI>Install</UI>.
      </li>
    </ol>
  );
}

const parts: GuidePart[] = [
  {
    id: "before",
    title: "Before you start",
    body: (
      <>
        <p>
          Porch isn’t in the App Store yet. During the pilot, you install it through Apple’s TestFlight app, which is
          how Apple lets people test new apps.
        </p>
        <ul>
          <li>
            <strong>Your private setup link</strong> comes from me by email or text. It sets up one iPad and lasts 14
            days.
          </li>
          <li>
            <strong>The Porch phone adapter</strong> comes from me too, by mail or in person. You can set up everything
            else before it arrives and connect the phone later.
          </li>
        </ul>
        <Tip>
          <p>Set aside about 30 minutes, with the iPad, the phone, the adapter and your own iPhone all within reach.</p>
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
            <strong>Charge it and connect it to Wi-Fi.</strong> Use the Wi-Fi where your loved one lives, if you can.
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
            <strong>Set the phone to tone dialing.</strong> Most big-button phones have a switch on the side or bottom
            marked <UI>T / P</UI> or <UI>Tone / Pulse</UI>. Set it to <UI>T</UI>. Porch can’t hear pulse dialing.
          </li>
        </ol>
        <Tip label="An older iPad?">
          <p>
            If the iPad’s charging port is the older, narrow Lightning kind rather than USB-C, tell me before you buy a
            hub. It needs a different adapter.
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
          In TestFlight the app is called Porch Family Calling. On the Home Screen it’s just Porch. It’s the same app on
          the iPad and on iPhones.
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
          On the iPad, open the email or text with your private setup link and tap it. Porch opens straight to{" "}
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
            Open the setup link on the iPad that will stay with your loved one, not on your iPhone. On an iPhone, Porch
            only explains that the link is for the iPad.
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
            Six digits, entered twice. You’ll use it to change Porch’s settings, on the iPad and from your iPhone.{" "}
            <strong>Write it down somewhere safe.</strong>
          </li>
          <li>
            <strong>
              <UI>[Name]’s Porch number</UI>
            </strong>{" "}
            Every Porch gets its own phone number, so people can call your loved one from any phone. Porch suggests an area code
            near the iPad. Tap <UI>Get number</UI>, or <UI>Use a different area code</UI> to pick another. It can take a
            little while. When the number appears, tap <UI>Continue</UI>.
          </li>
          <li>
            <strong>
              <UI>Microphone and camera</UI>
            </strong>{" "}
            Tap <UI>Continue</UI>, then <UI>Allow</UI> for each. Without them, family can’t hear or see your loved one.
          </li>
          <li>
            <strong>
              <UI>How will [Name] call?</UI>
            </strong>{" "}
            Choose <UI>Corded phone</UI>. The next part walks through it. If the adapter hasn’t arrived yet, choose it
            anyway and tap <UI>Do this later</UI> on the next screen.
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
          Porch shows <UI>Connect the phone</UI>. On an iPad, the phone goes through the Cell2Jack and then the Porch
          phone adapter, which turns the phone’s keys into something the iPad understands. Plug it all in this way:
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
            Porch says <Says>Lift the receiver and press a key.</Says> Do that, and Porch answers{" "}
            <Says>Porch heard 3. Now put the receiver back.</Says> Keys you press here don’t call anyone.
          </li>
          <li>
            Hang up. Porch says <Says>Porch heard you hang up. The phone is ready.</Says> Tap <UI>Continue</UI>.
          </li>
        </ol>
        <Tip label="Not working?">
          <ul>
            <li>Check the hub’s charger is plugged in, so the iPad can power the adapter and the Cell2Jack.</li>
            <li>
              If the adapter’s light keeps blinking, unplug the Cell2Jack from it for ten seconds and plug it back in.
            </li>
            <li>If the light never comes on, try another USB-C cable. Some cables only charge.</li>
            <li>Check the phone is set to tone dialing.</li>
            <li>The keys only work while the receiver is lifted.</li>
            <li>
              If the Cell2Jack announces the phone isn’t connected when you lift the receiver, press a key and it stops.
            </li>
          </ul>
        </Tip>
        <p>
          Adapter not here yet? Tap <UI>Do this later</UI>. Your loved one can use the touchscreen meanwhile. When it arrives,
          open caregiver mode, then <UI>This iPad</UI>, and tap <UI>Connect the phone</UI>.
        </p>
        <p>
          The phone is the keypad. Calls themselves use the iPad’s speaker, microphone and camera, so your loved one sees and hears
          family on the screen.
        </p>
      </>
    ),
  },
  {
    id: "your-phone",
    title: "Add your iPhone",
    body: (
      <>
        <p>
          The iPad now shows <UI>Add your phone</UI>. Your iPhone becomes the caregiver’s phone: you can call your loved one, send
          messages and change settings from it.
        </p>
        <ol>
          <li>
            <strong>Install Porch on your iPhone first.</strong> Get TestFlight and Porch the same way you did on the
            iPad. With an Android phone, send me its Google account first, so I can add you to Porch’s Google Play test,
            then install Porch from the test link I send you.
          </li>
          <li>
            On the iPad, type your name and tap <UI>Show QR code</UI>. Your name is how Porch tells your loved one who’s calling.
          </li>
          <li>
            Open the Camera on your iPhone and point it at the code. Tap the link that appears. Porch opens with the
            invitation filled in. Tap <UI>Join family</UI>.
          </li>
          <li>
            Your iPhone asks to send notifications and use the microphone. Allow both, so Porch can ring your iPhone
            even when it’s locked.
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
        <p>If the link opens a web page instead of Porch, tap <UI>Open invitation in Porch</UI>. If that doesn’t work:</p>
        <ul>
          <li>
            Tap <UI>Copy invitation</UI>, open Porch, tap <UI>I’m joining my family</UI>, paste it into{" "}
            <UI>Porch invitation</UI> and tap <UI>Join family</UI>.
          </li>
          <li>
            Or, on the iPad, tap <UI>Send the invitation instead</UI> and send it to yourself.
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
    title: "Put people on the keypad",
    body: (
      <>
        <p>
          Each number key on the phone can call one person. Your loved one lifts the receiver and presses that person’s key. Set the keys
          up on the iPad.
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
            Under <UI>What key 1 does</UI>, choose <UI>Call a person</UI>.
          </li>
          <li>
            Under <UI>Their details</UI>:
            <ul>
              <li>
                For someone who has joined your loved one’s Porch, such as you, tap <UI>Choose from Family on Porch</UI>.
              </li>
              <li>
                Otherwise type their name, or tap <UI>Choose from Contacts</UI>. You can tap <UI>Invite them</UI> to
                send them an invitation.
              </li>
              <li>
                Under <UI>Calls start as</UI>, choose video or audio.
              </li>
            </ul>
          </li>
          <li>
            Under <UI>Photo &amp; button color</UI>, tap <UI>Add photo</UI>.
          </li>
          <li>
            Turn on <UI>Call their phone</UI> and enter their <UI>Primary number</UI>. If Porch isn’t answered in 20
            seconds, Porch rings that number instead, voice only. Start numbers outside the US with +.
          </li>
          <li>
            Tap <UI>Save</UI>. Repeat for each key.
          </li>
        </ol>
        <Tip>
          <p>
            Keys 0 and 9 control calls: 0 answers and hangs up, and 9 turns video on and off. Use 1 to 8 for people.
            Many big-button phones have room for a photo on each key, which makes them easier for your loved one to find.
            Use the <Link href="/labels">phone button label maker</Link> to print photos and names at the right size.
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
            Type their name. Leave <UI>Audio drop-in</UI> and <UI>Video drop-in</UI> on if they may drop in without your loved
            one having to answer. Turn on <UI>Caregiver mode</UI> only for someone who should change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI> and send it by text or email. Then tap <UI>Done</UI>.
          </li>
        </ol>
        <p>
          An invitation works once, within 24 hours. The link shows them how to get Porch. On an iPhone, that’s
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
    title: "Make a test call",
    body: (
      <>
        <h3>Call your loved one from your iPhone</h3>
        <p>
          With the clock showing on the iPad, tap <UI>Video call</UI> in Porch on your iPhone. Because you’re approved
          to drop in, the iPad says who’s dropping in and connects after five seconds, without your loved one touching anything.
          They can press 0 or tap <UI>Don’t connect</UI> to stop it.
        </p>
        <p>
          A relative who isn’t approved rings instead. The iPad shows <UI>Incoming video call</UI>. Your loved one taps{" "}
          <UI>Answer video call</UI>, or presses 0 on the phone.
        </p>
        <h3>Call you from the iPad</h3>
        <p>
          Lift the receiver and press your key. The iPad says <Says>Calling</Says> and your name, and your iPhone
          rings like a regular phone call, even when it’s locked. Put the receiver back to hang up.
        </p>
        <p>
          If you don’t answer, Porch rings your regular phone number, if you added one, and that phone’s own voicemail
          can take a message. Without a number, your loved one can leave you a message in Porch.
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
            <strong>To answer,</strong> press 0 on the phone, or tap the answer button. To decline, tap{" "}
            <UI>Decline</UI> on the screen.
          </li>
          <li>
            <strong>To hang up,</strong> put the receiver back, or press 0.
          </li>
          <li>
            <strong>Messages</strong> from family wait on the iPad until your loved one plays them.
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
      <p>
        Porch can speak English, Mandarin, Cantonese, Spanish, Tagalog and Korean. On the iPad, open caregiver mode,
        then <UI>Display &amp; voice</UI>, and choose under <UI>Bedside language</UI>.
      </p>
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
          <strong>Keep Porch in front, if your loved one tends to wander into other apps,</strong> with Apple’s Guided Access: in{" "}
          <UI>Settings</UI>, open <UI>Accessibility</UI>, then <UI>Guided Access</UI>. In its options, leave{" "}
          <UI>Touch</UI> and <UI>Software Keyboards</UI> on. Pause it when you need to type in Porch.
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
                Lift the receiver first: the keys only work while it’s off the cradle. Check the adapter’s red light is
                on and the hub’s charger is plugged in. Then open caregiver mode, <UI>This iPad</UI>, and run{" "}
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
                The iPad is off, out of charge, off Wi-Fi, or Porch isn’t open. Check it’s plugged in and connected to
                Wi-Fi, and that Porch is showing the clock.
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
            q: "Porch won’t open, or says it has expired.",
            a: (
              <p>
                Each test version lasts 90 days. Open TestFlight and tap <UI>Update</UI> next to Porch.
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

export default function IOSGuide() {
  return (
    <Guide
      eyebrow="Porch pilot guide"
      title={
        <>
          Get started on <em>iPad and iPhone.</em>
        </>
      }
      lede={
        <p>
          Everything you need to set up Porch on your loved one’s iPad, connect their big-button phone, and get the
          family calling from their own phones.
        </p>
      }
      aside={<>Using the other kind? <Link href="/pilot/android">The Android guide</Link></>}
      kit={{
        intro: "On an iPad, the phone also goes through the Porch phone adapter, a small board I set up, test and send you.",
        parts: kit,
        ready: [
          "Wi-Fi where your loved one lives, and its password.",
          "Your private setup link, from me.",
          "Your own iPhone to pair as the caregiver’s phone. An Android phone works too.",
          "A few photos of the people your loved one calls most, for their keys.",
        ],
      }}
      parts={parts}
    />
  );
}
