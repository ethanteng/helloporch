import Link from "next/link";
import { Contact, Defaults, Guide, guideMetadata, Path, Says, Screenshot, Setting, Tip, UI, type GuidePart } from "../_guide/parts";

export const metadata = guideMetadata(
  "Porch features and settings | HelloPorch",
  "How to make calls, send messages and change Porch settings on tablets and family phones.",
);

// Defaults come from household setup in lib/family/service.ts and from the apps' own settings.

const parts: GuidePart[] = [
  {
    id: "settings",
    title: "Open caregiver mode",
    body: (
      <>
        <p>
          Use the six-digit PIN you chose during setup to open <strong>caregiver mode</strong> and change settings.
        </p>
        <ul>
          <li>
            <strong>On the tablet.</strong> Tap the gear in the top right corner of the clock. Enter the PIN and tap{" "}
            <UI>Open caregiver mode</UI>. Tap <UI>Back to clock</UI> when you’re done.
          </li>
          <li>
            <strong>On a caregiver’s phone.</strong> On an iPhone, tap your photo or the person icon in the top right,
            then <UI>Caregiver mode</UI>. On Android, tap <UI>Caregiver mode</UI> under your loved one’s name. Enter
            the PIN. Tap <UI>Done</UI> to close caregiver mode. It locks after 10 minutes without use.
          </li>
        </ul>
        <Screenshot
          src="/pilot/screens/ipad-keypad.png"
          width={1600}
          height={1112}
          device="tablet"
          alt="Caregiver mode on the iPad. The menu on the left lists People, Calls, Drop-in, Messages, Display & voice, Privacy, Caregivers & PIN and This iPad, with People open on the right."
          caption="Caregiver mode on the iPad. The settings in this guide start from the menu on the left."
        />
        <p>
          Settings marked <em>tablet only</em> must be changed on your loved one’s tablet. On a caregiver’s phone,
          they appear with a lock under <UI>On the bedside iPad</UI> or <UI>On the bedside tablet</UI>.
        </p>
        <p>Where you see [Name] in this guide, Porch shows the name you entered during setup.</p>
        <Tip label="Return to the clock after changing settings">
          <p>
            While caregiver mode is open on the tablet, drop-ins don’t connect. Tap <UI>Back to clock</UI> when
            you’re finished.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "defaults",
    title: "Settings when you first set up Porch",
    body: (
      <>
        <Defaults
          rows={[
            ["Drop-in", "On", <Path key="p" steps={["Drop-in", "Allow drop-ins"]} />],
            ["Who may drop in", "Everyone you invite, with audio and video", <>Each person’s page, or the invitation</>],
            ["Caregiver access for people you invite", "Off", <>Each person’s page</>],
            ["Calls from unknown numbers", "Blocked", <Path key="p" steps={["Calls", "Block unknown callers"]} />],
            ["How long a call to the tablet rings", "45 seconds", <><Path steps={["Calls", "Ring before voicemail"]} />, tablet only</>],
            ["Try a regular phone after a missed Porch call", "After 20 seconds, if the key has a phone number", <><Path steps={["Calls", "Try their phone after"]} />, tablet only</>],
            ["Leave a message after an unanswered call from the tablet", "Offered unless the call went to a regular phone", <><Path steps={["Calls", "Leave a message if no one answers"]} />, tablet only</>],
            ["End calls after silence", "On, after 2 minutes", <><Path steps={["Calls", "End calls after silence"]} />, tablet only</>],
            ["Family messages", "On", <Path key="p" steps={["Messages", "Allow family messages"]} />],
            ["Voicemail and texts from unknown numbers", "Held for a caregiver to review", <Path key="p" steps={["Messages", "Waiting messages"]} />],
            ["Playing messages when someone is in front of the tablet", "On, from 8 AM until 9 PM", <><Path steps={["Messages", "Play when someone is in front of the iPad"]} />, tablet only</>],
            ["Showing family when someone was at the tablet", "On, from touches and key presses", <Path key="p" steps={["Privacy", "Show family when someone is at the iPad"]} />],
            ["Using the camera to notice someone", "On", <><Path steps={["Privacy", "Check with the camera"]} />, tablet only</>],
            ["Language", "English", <><Path steps={["Display & voice", "Bedside language"]} />, tablet only</>],
            ["Announcement voice", "Porch’s voice", <><Path steps={["Display & voice", "Announcement voice"]} />, tablet only</>],
            ["Clock", "Day & night", <><Path steps={["Display & voice", "Clock"]} />, tablet only</>],
            ["Keypad", "0 answers and hangs up, 9 turns video off and on, and the other keys are empty", <><Path steps={["People"]} />, tablet only</>],
            ["A new keypad person’s calls", "Start as video", <>The key’s <UI>Calls start as</UI>, tablet only</>],
            ["Putting the receiver back hangs up", "On", <><Path steps={["This iPad", "Hang up when the receiver is put back"]} />, tablet only</>],
            ["Your camera at the start of video calls", "On", <>Your own Porch settings: <UI>Start video calls with my camera on</UI></>],
          ]}
        />
      </>
    ),
  },
  {
    id: "keypad",
    title: "Set up the phone’s number keys",
    body: (
      <>
        <p>
          Lift the receiver and press the key for the person you want to call. On the tablet, you can also tap{" "}
          <UI>Call someone</UI> and choose a name.
        </p>
        <h3>Put someone on a key</h3>
        <ol>
          <li>
            On the tablet, open <Path steps={["People"]} /> and tap an empty key.
          </li>
          <li>
            Choose <UI>Call a person</UI> under the heading for that key, such as <UI>What key 1 does</UI>.
          </li>
          <li>
            Under <UI>Their details</UI>, tap <UI>Choose from Family on Porch</UI> for someone who already uses Porch.
            For anyone else, type their name or tap <UI>Choose from Contacts</UI>. You can invite them with{" "}
            <UI>Invite them</UI>.
          </li>
          <li>
            Under <UI>Calls start as</UI>, choose video or audio. Add a photo under{" "}
            <UI>Photo &amp; button color</UI>.
          </li>
          <li>
            To let Porch call their regular phone, <a href="#phone-fallback">add their phone number</a>. Tap <UI>Save</UI>.
          </li>
        </ol>
        <p>
          To move someone, tap them under <UI>People</UI>, then <UI>Keypad key</UI>, and pick another key or{" "}
          <UI>Take off the keypad</UI>.
        </p>
        <p>
          To put each person’s photo and name on their key, print labels with the{" "}
          <Link href="/labels">phone button label maker</Link>. The setup guides walk through it.
        </p>
        <h3>What else a key can do</h3>
        <ul>
          <li>
            <UI>Answer / decline / hang up</UI> answers a ringing call, stops a drop-in before it connects or ends
            a call. To decline a ringing call, tap <UI>Decline</UI> on the screen.
          </li>
          <li>
            <UI>Turn video off / on</UI> controls the tablet’s camera during a video call.
          </li>
          <li>
            <UI>Play / stop messages</UI> plays waiting messages. You can assign it to * or #.
          </li>
          <li>
            <UI>No action</UI> leaves the key unused.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Key 0 answers calls, stops drop-ins and hangs up. Key 9 turns the camera off and on. The other keys are empty."],
            ["Change it", <><Path key="p" steps={["People"]} />, then tap a key. Tablet only.</>],
            ["New keys", <>Calls start as video when you set up the key under <UI>People</UI>. If you assign a key from someone’s page using <UI>Keypad key</UI>, their calls start as audio.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "phone-fallback",
    title: "Try a regular phone after a missed call",
    body: (
      <>
        <p>
          If someone misses a call in the Porch app, Porch can try their regular phone number. The second call is
          voice only and shows your loved one’s Porch number.
        </p>
        <h3>Add a phone number</h3>
        <ol>
          <li>
            On the tablet, open <Path steps={["People"]} /> and tap the person.
          </li>
          <li>
            Tap <UI>Phone</UI>, turn on <UI>Call their phone</UI> and enter their <UI>Primary number</UI>.
          </li>
          <li>
            Use <UI>Add another number</UI> for any other numbers they call from. You can save up to five numbers per
            person. Porch places calls to the primary number.
          </li>
          <li>
            Tap <UI>Save</UI>.
          </li>
        </ol>
        <p>
          If the person only has a phone number on their key, Porch calls that number right away. If nobody answers
          a regular phone call, the phone’s voicemail can take a message.
        </p>
        <Setting
          rows={[
            ["Default", "Porch tries their phone after 20 seconds, for anyone whose key has a phone number."],
            ["Change the wait", <><Path key="p" steps={["Calls", "Try their phone after"]} />, from 5 seconds to 2 minutes. Tablet only.</>],
            ["Turn it off", <>For one person, turn off <UI>Call their phone</UI> on their page.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "calling",
    title: "Calling your loved one",
    body: (
      <>
        <ul>
          <li>
            In Porch on your phone, tap <UI>Audio call</UI> or <UI>Video call</UI>.
          </li>
          <li>
            If you’re approved to drop in and the clock is showing on the tablet, the call connects by itself. See{" "}
            <a href="#drop-in">Drop-in</a>.
          </li>
          <li>
            Otherwise the tablet rings. To answer a video call, your loved one can tap <UI>Answer video call</UI> or
            lift the receiver and press 0. To decline, tap <UI>Decline</UI>.
          </li>
          <li>
            If nobody answers, Porch offers to <UI>Leave a message</UI>.
          </li>
          <li>Calls have no time limit.</li>
        </ul>
        <p>
          People without the app can call your loved one’s <a href="#porch-number">Porch number</a> from a regular phone.
        </p>
        <Setting
          rows={[
            ["Default", "A call rings the tablet for 45 seconds. Your camera is on when a video call starts."],
            ["Change the ring time", <><Path key="p" steps={["Calls", "Ring before voicemail"]} />, from 15 seconds to 2 minutes. Tablet only. It also applies to calls from regular phones.</>],
            ["Start with your camera off", <>In your own Porch settings, turn off <UI>Start video calls with my camera on</UI>.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "drop-in",
    title: "Drop-in calls",
    body: (
      <>
        <p>
          A drop-in connects without anyone answering. Porch chimes, says who’s calling and waits five seconds before
          connecting.
        </p>
        <ul>
          <li>
            In Porch on your phone, tap <UI>Drop in with video</UI> or <UI>Drop in with audio</UI>. An approved
            person’s <UI>Video call</UI> and <UI>Audio call</UI> drop in too.
          </li>
          <li>
            Your loved one can stop it by tapping <UI>Don’t connect</UI> or pressing 0.
          </li>
          <li>Drop-ins only connect on their own while the clock is showing on the tablet.</li>
        </ul>
        <h3>Choose who may drop in</h3>
        <ul>
          <li>
            To pause drop-ins for everyone, turn off <Path steps={["Drop-in", "Allow drop-ins"]} />. Porch remembers who
            you approved.
          </li>
          <li>
            To change access for one person, tap their name under <UI>Drop-in</UI> or <UI>People</UI>. Turn <UI>Audio drop-in</UI> or{" "}
            <UI>Video drop-in</UI> on or off.
          </li>
          <li>
            For new people, use the <UI>Approve drop-in</UI> switches on the invitation.
          </li>
        </ul>
        <h3>Drop in from a regular phone</h3>
        <p>
          For someone who uses a regular phone, open <Path steps={["Drop-in", "Add a phone number"]} /> and turn on{" "}
          <UI>Approve audio drop-in</UI>. The call drops in if the phone company confirms the caller’s number. Otherwise
          the tablet rings.
        </p>
        <Setting
          rows={[
            ["Default", "On. Everyone you invite may drop in with audio and video, and so may your own phone from setup."],
            ["Change it", <><Path key="p" steps={["Drop-in"]} />, on the tablet or a caregiver’s phone.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "messages",
    title: "Video and voice messages",
    body: (
      <>
        <h3>Send a message</h3>
        <ol>
          <li>
            In Porch on your phone, tap <UI>Send a message</UI>.
          </li>
          <li>
            Tap <UI>Record a video</UI> or <UI>Record audio</UI>. Messages can be up to two minutes.
          </li>
          <li>
            Tap <UI>Play it back</UI> to check it, then <UI>Send to [Name]</UI>.
          </li>
        </ol>
        <p>
          <UI>Messages with [Name]</UI> shows whether each one has played. Until it plays, you can <UI>Unsend</UI> it.
        </p>
        <h3>Play messages</h3>
        <ul>
          <li>
            Tap <UI>Play 1 message</UI> on the clock screen, or press a key set to <UI>Play / stop messages</UI>.
            Tap <UI>Stop</UI> to stop playback.
          </li>
          <li>
            Porch says who each message is from and when it was sent.
          </li>
          <li>A message that isn’t played within a week is removed.</li>
        </ul>
        <Setting
          rows={[
            ["Default", "On."],
            ["Change it", <><Path key="p" steps={["Messages", "Allow family messages"]} />, on the tablet or a caregiver’s phone.</>],
            ["When it’s off", <>Family phones hide <UI>Send a message</UI>, unanswered calls don’t offer one, and people calling the Porch number can’t leave voicemail.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "autoplay",
    title: "Play messages automatically",
    body: (
      <>
        <ul>
          <li>
            With <Path steps={["Messages", "Play when someone is in front of the iPad"]} /> on, Porch uses the camera
            to see if someone is there, then announces and plays waiting messages. It doesn’t record video.
          </li>
          <li>
            Choose the hours with <UI>Starting at</UI> and <UI>Until</UI>, so messages don’t play in the night.
          </li>
          <li>
            If your loved one taps <UI>Not now</UI> or <UI>Stop</UI>, Porch waits 30 minutes before trying again.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "On, from 8 AM until 9 PM."],
            ["Change it", "On the tablet only."],
            ["Android", <>The switch is <UI>Play when someone is in front of the tablet</UI>.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "no-answer",
    title: "When nobody answers",
    body: (
      <>
        <ul>
          <li>
            <strong>From the tablet.</strong> If the call stays in Porch, the tablet asks your loved one to speak after
            the beep. Press 0 when finished, then tap <UI>Send message</UI> or <UI>Don’t send</UI>. Sent messages appear
            under <UI>Messages with [Name]</UI> on the family member’s phone. If Porch tried a regular phone, that
            phone’s voicemail can take the message.
          </li>
          <li>
            <strong>From a family phone.</strong> When Porch asks <Says>Leave a message?</Says>, tap{" "}
            <UI>Leave a message</UI> to record one or <UI>Not now</UI>.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "On, both ways."],
            ["Change it", <>For calls from the tablet, <Path key="p" steps={["Calls", "Leave a message if no one answers"]} />, tablet only. For calls to it, <UI>Allow family messages</UI>.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "porch-number",
    title: "Your loved one’s Porch phone number",
    body: (
      <>
        <ul>
          <li>
            Porch gets a US phone number during setup. Keep it in your contacts so you know who’s calling.
          </li>
          <li>
            On a family phone, under <UI>[Name]’s Porch number</UI>, tap <UI>Add to Contacts</UI> or{" "}
            <UI>Share this number</UI>, which sends it by text with a contact card.
          </li>
          <li>
            A call to the Porch number rings on the tablet. If nobody answers, the caller can leave a voicemail.
          </li>
          <li>
            Porch <a href="#blocking">blocks unknown numbers</a> by default.
          </li>
        </ul>
        <Setting
          rows={[
            ["See it", <>At the top of caregiver mode, under <UI>Porch number</UI>, or on any family phone.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "blocking",
    title: "Block unknown callers",
    body: (
      <>
        <ul>
          <li>
            Porch lets through numbers saved on the keypad, numbers approved for drop-ins and numbers you allow.
            It blocks calls with a hidden number.
          </li>
          <li>
            To let a blocked number through, open <Path steps={["Calls", "Blocked numbers"]} /> and tap <UI>Allow</UI>{" "}
            next to the number.
          </li>
          <li>
            Allowed numbers are listed under <UI>Allowed</UI>, each with <UI>Remove</UI>.
          </li>
          <li>
            <UI>Clear this list</UI> only empties the list. Those numbers stay blocked.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "On."],
            ["Change it", <><Path key="p" steps={["Calls", "Block unknown callers"]} />, on the tablet or a caregiver’s phone. When it’s off, calls from unfamiliar numbers can ring.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "voicemail-texts",
    title: "Voicemail and texts to the Porch number",
    body: (
      <>
        <ul>
          <li>
            <strong>Voicemail</strong> from a number on the keypad plays on the tablet like a family message. Voicemail
            from anyone else waits for a caregiver.
          </li>
          <li>
            <strong>Texts</strong> from numbers saved on the keypad, approved for drop-ins or allowed by a caregiver
            appear on the tablet. Porch reads them aloud and translates them if needed. Porch can show text only.
            Texts from other numbers wait for a caregiver to review.
          </li>
          <li>
            A caregiver’s phone shows <UI>1 phone voicemail needs your review</UI> or <UI>1 text needs your review</UI>.
          </li>
          <li>
            In <Path steps={["Messages", "Waiting messages"]} />, tap <UI>Listen first</UI>, then{" "}
            <UI>Let it play on Porch</UI> or <UI>Let it show on Porch</UI>, or <UI>Remove</UI>.
          </li>
          <li>Texts nobody reads within a week are removed.</li>
        </ul>
        <Setting
          rows={[
            ["Default", "On. Porch holds messages from unknown numbers for review."],
            ["Turn it off", <>Turn off <UI>Allow family messages</UI> to stop family messages, voicemail and texts.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "three-way",
    title: "Add someone to a call",
    body: (
      <>
        <ol>
          <li>
            During a call with your loved one, tap <UI>Add someone</UI> on your phone.
          </li>
          <li>
            Choose a family member to call. If you’re a caregiver, you can also choose{" "}
            <UI>A phone number…</UI>, enter who you’re calling and their number, and tap{" "}
            <UI>Call and add to this call</UI>.
          </li>
          <li>
            To remove someone, tap <UI>Hang up [their name]</UI>. If you hang up, anyone you added by phone number is
            disconnected too.
          </li>
        </ol>
        <Setting
          rows={[
            ["Default", "Anyone in the family can add a family member. Only caregivers can add a phone number."],
            ["Limits", "You can add US and Canadian numbers, including toll-free numbers. Add people from your family phone."],
          ]}
        />
      </>
    ),
  },
  {
    id: "abroad",
    title: "Call family in other countries",
    body: (
      <>
        <ul>
          <li>You can call between Porch apps over the internet, including from other countries.</li>
          <li>
            To save a phone number outside the US on a key, start it with + and the country code. Porch checks it when
            you tap <UI>Save</UI>.
          </li>
          <li>
            If Porch says it can’t call numbers in that country yet, <Contact /> and I can turn that country on.
          </li>
          <li>
            Calls from a regular phone abroad ring on the tablet. You can only add US and Canadian phone numbers to a
            call already in progress.
          </li>
        </ul>
        <Setting
          rows={[
            ["Regular phone calls", "US and Canadian numbers are enabled. Ask me to enable another country."],
          ]}
        />
      </>
    ),
  },
  {
    id: "language",
    title: "Language, voice and clock",
    body: (
      <>
        <ol>
          <li>
            On the tablet, open <Path steps={["Display & voice"]} />.
          </li>
          <li>
            Under <UI>Bedside language</UI>, choose English, Mandarin (traditional or simplified characters),
            Cantonese, Spanish, Tagalog or Korean.
          </li>
          <li>
            Under <UI>Announcement voice</UI>, choose a Porch voice (listed as Natural) or one of the tablet’s voices. Tap{" "}
            <UI>Preview announcement</UI> to hear it.
          </li>
          <li>
            Under <UI>Clock</UI>, choose <UI>Dark</UI> or <UI>Day &amp; night</UI>. With <UI>Day &amp; night</UI>,
            you can set when the clock switches between the two.
          </li>
          <li>
            Tap <UI>Save</UI>.
          </li>
        </ol>
        <p>
          The language also sets how Porch greets people who reach voicemail on the Porch number, and which language
          texts are translated into. Caregiver mode and the family apps stay in English.
        </p>
        <Setting
          rows={[
            ["Default", "English, Porch’s voice and the Day & night clock."],
            ["Change it", "Tablet only."],
            ["Use a tablet voice", <>Choose <UI>System default</UI> or select a voice from the list.</>],
            ["Android", <>If Porch says no voice is available for a language, add one in Android’s <UI>Settings</UI>, under <UI>Accessibility</UI>, <UI>Text-to-speech output</UI>.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "presence",
    title: "Share when someone uses the tablet",
    body: (
      <>
        <ul>
          <li>
            Family phones show <UI>Someone is at the iPad</UI>, or <UI>Someone was at the iPad 12 minutes ago</UI>.
            Android says “tablet”.
          </li>
          <li>Porch updates this status when someone touches the screen or presses a key.</li>
          <li>
            With <UI>Check with the camera</UI> on, Porch also checks for someone in front of the tablet about every
            30 seconds. It doesn’t record video.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Sharing is on. Touches, key presses and the camera check all count."],
            ["Change it", <><Path key="p" steps={["Privacy", "Show family when someone is at the iPad"]} />, on the tablet or a caregiver’s phone. <UI>Check with the camera</UI> is on the tablet only.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "history",
    title: "Call history, silence and test sounds",
    body: (
      <>
        <ul>
          <li>
            <Path steps={["Calls", "Call history"]} /> lists the last 90 days of calls: who called whom, how long they
            talked, and missed or declined calls. It’s on the tablet and caregivers’ phones.
          </li>
          <li>
            <Path steps={["Calls", "End calls after silence"]} /> hangs up a call after nobody has talked for a while.
            Choose how long with <UI>After no one talks for</UI>.
          </li>
          <li>
            <Path steps={["Calls", "Test sounds"]} /> plays the ringing and the drop-in announcement, to check the
            volume. Tablet only.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Ending silent calls is on, after 2 minutes. You can set it to 1–30 minutes, or turn it off."],
            ["Change it", "Tablet only."],
          ]}
        />
      </>
    ),
  },
  {
    id: "desk-phone",
    title: "The big-button phone",
    body: (
      <>
        <p>
          Use the phone’s keys to call, answer or hang up. You’ll see and hear the caller on the tablet and speak
          into the tablet’s microphone.
        </p>
        <ul>
          <li>To answer, lift the receiver and press 0.</li>
          <li>Putting the receiver back hangs up.</li>
          <li>
            To check the phone again, open <Path steps={["This iPad", "Connect the phone"]} />. On Android it’s{" "}
            <UI>This tablet</UI>.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", <>Putting the receiver back hangs up.</>],
            ["Change it", <><Path key="p" steps={["This iPad", "Hang up when the receiver is put back"]} />, tablet only. Turn it off to keep calls connected when someone puts the receiver back.</>],
            ["Android", <>The same switch is under <UI>This tablet</UI>.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "people",
    title: "Family, caregivers and invitations",
    body: (
      <>
        <h3>Invite someone</h3>
        <ol>
          <li>
            Open <Path steps={["People", "Invite someone"]} /> on the tablet, or <Path steps={["Family", "Invite someone"]} />{" "}
            on your phone.
          </li>
          <li>
            Type their name. Choose whether they may drop in with audio and video, and whether they get caregiver mode.
          </li>
          <li>
            Tap <UI>Create invitation</UI> and share it. It works once, within 24 hours.
          </li>
        </ol>
        <p>
          To cancel an unused invitation, find it under <UI>Invited</UI> and tap <UI>Cancel</UI>.
        </p>
        <h3>Change what someone can do</h3>
        <p>Tap their name under <UI>People</UI> or <UI>Family</UI>.</p>
        <ul>
          <li>
            Change the name and photo your loved one sees. Tap <UI>Use their own photo</UI> to go back to the
            photo they chose.
          </li>
          <li>
            Turn <UI>Audio drop-in</UI> and <UI>Video drop-in</UI> on or off.
          </li>
          <li>
            Turn on <UI>Caregiver mode</UI> to let them change settings from their phone with the PIN.
          </li>
          <li>
            Tap <UI>Remove [Name]</UI> to remove them. They’ll need a new invitation to rejoin.
          </li>
        </ul>
        <p>
          To rename your loved one’s Porch, tap its name at the top of caregiver mode.
        </p>
        <Setting
          rows={[
            ["Default", "People you invite can drop in with audio and video. Caregiver access is off for new invitations and on for the phone you added during setup."],
            ["Change it", "On the tablet or a caregiver’s phone."],
          ]}
        />
      </>
    ),
  },
  {
    id: "pin",
    title: "The caregiver PIN",
    body: (
      <>
        <ul>
          <li>
            To change it, open <Path steps={["Caregivers & PIN", "Change caregiver PIN"]} /> on the tablet. Enter the
            current PIN, then the new one twice, and tap <UI>Save new PIN</UI>.
          </li>
          <li>
            Turn caregiver access on or off for each person in the same place, or on their page.
          </li>
          <li>After five wrong PIN entries, wait 15 minutes before trying again.</li>
          <li>
            If you forget the PIN, <Contact /> for help resetting it.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: "your-app",
    title: "Settings on your phone",
    body: (
      <>
        <ul>
          <li>
            <strong>Change your name or photo.</strong> On an iPhone, tap your photo or the person icon in the top right.
            On Android, tap <UI>Your name and photo</UI>.
          </li>
          <li>
            To start video calls with your camera off, turn off <UI>Start video calls with my camera on</UI>.
          </li>
          <li>
            Tap <UI>Join another family</UI> to add another loved one. One phone can join up to four Porches.
          </li>
          <li>
            On Android, tap <UI>Leave this family</UI> to leave. On an iPhone, you can leave from the app if you’ve
            joined two or more families. If you’ve joined one, ask a caregiver to remove you.
          </li>
          <li>
            Allow notifications so Porch can ring when the app is closed. Allow microphone access so the other
            person can hear you. On Android, tap <UI>Ring when Porch is closed</UI> if it appears.
          </li>
        </ul>
        <Setting rows={[["Default", "Your camera is on when a video call starts."]]} />
      </>
    ),
  },
  {
    id: "tablet",
    title: "Replacing or reusing the tablet",
    body: (
      <ul>
        <li>
          <strong>Move Porch to a new tablet.</strong> To get a link for the new tablet, <Contact />. Your loved
          one keeps their Porch number and family members. Set up the keys again on the new tablet.
        </li>
        <li>
          <strong>Use the tablet to call your loved one.</strong> On iPad, open{" "}
          <Path steps={["This iPad", "Use this iPad as a family device"]} />. On Android, choose{" "}
          <Path steps={["This tablet", "Use this tablet as a family device"]} />. On iPad you can switch back from
          Porch settings with <UI>Use this iPad as the bedside Porch</UI>.
        </li>
      </ul>
    ),
  },
  {
    id: "coming",
    title: "Help during the pilot",
    body: (
      <>
        <p>If you need help with any of these, <Contact />.</p>
        <ul>
          <li>Resetting a forgotten caregiver PIN.</li>
          <li>Deleting a Porch, its number and everything in it.</li>
          <li>Setting up the keypad again on a replacement tablet.</li>
        </ul>
      </>
    ),
  },
];

export default function FeaturesGuide() {
  return (
    <Guide
      eyebrow="Porch pilot guide"
      title={
        <>
          Porch <em>features and settings</em>
        </>
      }
      lede={
        <p>
How to make calls, send messages and change settings on your loved one’s tablet or your phone.
        </p>
      }
      aside={
        <>
          For first-time setup, use the <Link href="/pilot/ios">iPad guide</Link> or the{" "}
          <Link href="/pilot/android">Android tablet guide</Link>, and the <Link href="/pilot/phone">phone guide</Link>{" "}
          for family phones.
        </>
      }
      parts={parts}
    />
  );
}
