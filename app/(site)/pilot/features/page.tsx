import Link from "next/link";
import { Contact, Defaults, Guide, guideMetadata, Path, Says, Setting, Tip, UI, type GuidePart } from "../_guide/parts";

export const metadata = guideMetadata(
  "Every Porch feature | HelloPorch",
  "What each Porch feature does for your family, what it does out of the box, and how to change it or turn it off.",
);

// Every feature, on the iPad and iPhone apps and the Android apps, which have the same features. Labels are the
// apps' own; where Android's differ, the page says so.
// The defaults are a household set up from the app: drop-in on, unknown callers blocked, invitations approving audio
// and video drop-in (lib/family/service.ts), plus each app's own settings defaults.

const parts: GuidePart[] = [
  {
    id: "settings",
    title: "Where the settings are",
    body: (
      <>
        <p>
          Almost every setting is in <strong>caregiver mode</strong>, which the six-digit caregiver PIN from setup
          protects. You can open it on the tablet or on a caregiver’s phone.
        </p>
        <ul>
          <li>
            <strong>On the tablet:</strong> on an iPad, tap the gear on the clock. On Android, tap{" "}
            <UI>Caregiver mode</UI> in the top right corner. Enter the PIN and tap <UI>Open caregiver mode</UI>. Tap{" "}
            <UI>Back to clock</UI> when you’re done.
          </li>
          <li>
            <strong>On a caregiver’s phone:</strong> on an iPhone, tap your photo or the person icon in the top right
            corner, then <UI>Caregiver mode</UI>. On Android, tap <UI>Caregiver mode</UI> on the family’s card. Enter
            the PIN. Tap <UI>Done</UI> when you’re done. It also locks itself after 10 minutes without use.
          </li>
        </ul>
        <p>
          Some settings belong to the tablet itself, so you can only change them there: the keypad, the language, voice
          and clock, the PIN, the desk phone, and a few call settings. A phone shows these with a lock, under{" "}
          <UI>On the bedside iPad</UI> or <UI>On the bedside tablet</UI>.
        </p>
        <p>
          Below, a path such as <Path steps={["Calls", "Block unknown callers"]} /> starts in caregiver mode, and [Name]
          stands for the name you gave your loved one’s Porch.
        </p>
        <Tip label="Close caregiver mode on the tablet">
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
    title: "What Porch does out of the box",
    body: (
      <>
        <p>
          A Porch set up from the app starts like this. You don’t have to change anything for it to work, but each of
          these can be changed. Settings marked <em>tablet only</em> can only be changed on the tablet.
        </p>
        <Defaults
          rows={[
            ["Drop-in", "On", <Path key="p" steps={["Drop-in", "Allow drop-ins"]} />],
            ["Who may drop in", "Everyone you invite, with audio and video", <>Each person’s page, or the invitation</>],
            ["Caregiver access for people you invite", "Off", <>Each person’s page</>],
            ["Calls from unknown numbers", "Blocked", <Path key="p" steps={["Calls", "Block unknown callers"]} />],
            ["How long a call to the tablet rings", "45 seconds", <><Path steps={["Calls", "Ring before voicemail"]} />, tablet only</>],
            ["Ringing your regular phone when Porch isn’t answered", "After 20 seconds, for anyone whose key has a phone number", <><Path steps={["Calls", "Try their phone after"]} />, tablet only</>],
            ["A message when a call from the tablet isn’t answered", "Offered, unless the call went on to their regular phone", <><Path steps={["Calls", "Leave a message if no one answers"]} />, tablet only</>],
            ["Hanging up calls nobody is talking on", "Off", <><Path steps={["Calls", "End calls after silence"]} />, tablet only</>],
            ["Family messages", "On", <Path key="p" steps={["Messages", "Allow family messages"]} />],
            ["Voicemail and texts from unknown numbers", "Wait for a caregiver’s OK", <Path key="p" steps={["Messages", "Waiting messages"]} />],
            ["Playing messages when someone is in front of the tablet", "Off", <><Path steps={["Messages", "Play when someone is in front of the iPad"]} />, tablet only</>],
            ["Showing family when someone was at the tablet", "On, from touches and key presses", <Path key="p" steps={["Privacy", "Show family when someone is at the iPad"]} />],
            ["Using the camera to notice someone", "Off", <><Path steps={["Privacy", "Check with the camera"]} />, tablet only</>],
            ["Language", "English", <><Path steps={["Display & voice", "Bedside language"]} />, tablet only</>],
            ["Announcement voice", "A natural-sounding voice", <><Path steps={["Display & voice", "Announcement voice"]} />, tablet only</>],
            ["Clock", "Dark", <><Path steps={["Display & voice", "Clock"]} />, tablet only</>],
            ["Keypad", "0 answers and hangs up, 9 turns video off and on, and the other keys are empty", <><Path steps={["People"]} />, tablet only</>],
            ["A new keypad person’s calls", "Start as video", <>The key’s <UI>Calls start as</UI>, tablet only</>],
            ["Putting the receiver back hangs up", "On", <><Path steps={["This iPad", "Hang up when the receiver is put back"]} />, tablet only</>],
            ["Your camera at the start of video calls", "On", <>Your own Porch settings: <UI>Start video calls with my camera on</UI></>],
          ]}
        />
        <p>Calls have no time limit.</p>
      </>
    ),
  },
  {
    id: "keypad",
    title: "One-press calls from the keypad",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> your loved one never dials a number, scrolls a list or looks anyone up. They
          lift the receiver and press the key with your photo, and Porch calls you. They can also tap{" "}
          <UI>Call someone</UI> on the screen and tap a name.
        </p>
        <h3>Put someone on a key</h3>
        <ol>
          <li>
            On the tablet, open <Path steps={["People"]} /> and tap an empty key.
          </li>
          <li>
            Under <UI>What key 1 does</UI>, choose <UI>Call a person</UI>.
          </li>
          <li>
            Under <UI>Their details</UI>, tap <UI>Choose from Family on Porch</UI> for someone who has joined, or type a
            name, or tap <UI>Choose from Contacts</UI>. <UI>Invite them</UI> sends an invitation.
          </li>
          <li>
            Choose whether <UI>Calls start as</UI> video or voice, and add a photo under{" "}
            <UI>Photo &amp; button color</UI>.
          </li>
          <li>
            Add their phone number under <UI>Phone</UI> (see the next part), and tap <UI>Save</UI>.
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
            <UI>Answer / decline / hang up</UI>: answers a ringing call, and ends a call. To decline a call, tap{" "}
            <UI>Decline</UI> on the screen.
          </li>
          <li>
            <UI>Turn video off / on</UI>: turns their camera off and on during a video call.
          </li>
          <li>
            <UI>Play / stop messages</UI>: plays waiting messages. Putting this on * or # gives them a key for
            messages.
          </li>
          <li>
            <UI>No action</UI>: the key does nothing.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Key 0 answers, declines and hangs up. Key 9 turns video off and on. Every other key is empty. A new person’s calls start as video."],
            ["Change it", <><Path key="p" steps={["People"]} />, then tap a key. Tablet only.</>],
            ["Good to know", <>Adding someone from their own page with <UI>Keypad key</UI> starts their calls as voice. Check <UI>Calls start as</UI> on their page.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "phone-fallback",
    title: "If you miss the video call",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> your loved one still only presses once. If you don’t pick up in the Porch
          app, Porch rings your regular phone number, so you can still talk. That call is voice only, and it shows their
          Porch number.
        </p>
        <h3>Set it up for someone</h3>
        <ol>
          <li>
            On the tablet, open <Path steps={["People"]} /> and tap the person.
          </li>
          <li>
            Tap <UI>Phone</UI>, turn on <UI>Call their phone</UI> and enter their <UI>Primary number</UI>.
          </li>
          <li>
            Add any other numbers they call from under <UI>Add another number</UI>. Those can call in, but Porch only
            ever calls the primary number. Each person can have up to five.
          </li>
          <li>
            Tap <UI>Save</UI>.
          </li>
        </ol>
        <p>
          Someone who isn’t on Porch at all, with only a phone number on their key, gets a regular phone call straight
          away. Once a call goes to a regular phone and nobody picks up, that phone’s own voicemail answers.
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
        <p>
          <strong>Why it matters:</strong> family call from the Porch app on their own phone, with video, and your loved
          one sees and hears you on the tablet’s big screen.
        </p>
        <ul>
          <li>
            In Porch on your phone, tap <UI>Audio call</UI> or <UI>Video call</UI>.
          </li>
          <li>
            If you’re approved to drop in and the clock is showing on the tablet, the call connects by itself. See{" "}
            <a href="#drop-in">Drop-in</a>.
          </li>
          <li>
            Otherwise the tablet rings. Your loved one presses 0 on the phone or taps <UI>Answer video call</UI>, or
            taps <UI>Decline</UI>. Lifting the receiver alone doesn’t answer.
          </li>
          <li>
            If nobody answers, Porch offers to <UI>Leave a message</UI>.
          </li>
          <li>Calls have no time limit.</li>
        </ul>
        <p>
          Friends without the app can call their <a href="#porch-number">Porch number</a> from any phone instead.
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
    title: "Drop-in: Porch answers for them",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> for someone who can’t manage answering, the people you approve can connect
          without anyone touching anything. Porch chimes, says who’s dropping in, counts down five seconds, and
          connects.
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
            For everyone at once: <Path steps={["Drop-in", "Allow drop-ins"]} />. Turning it off pauses drop-ins and
            keeps everyone’s approvals for later.
          </li>
          <li>
            For one person: tap them under <UI>Drop-in</UI> or <UI>People</UI>, and turn <UI>Audio drop-in</UI> or{" "}
            <UI>Video drop-in</UI> on or off.
          </li>
          <li>
            When you invite someone: the <UI>Approve drop-in</UI> switches on the invitation.
          </li>
        </ul>
        <h3>Drop in from a regular phone</h3>
        <p>
          You can let a regular phone number drop in with audio, for someone who doesn’t use the app:{" "}
          <Path steps={["Drop-in", "Add a phone number"]} />, then <UI>Approve audio drop-in</UI>. It only works when
          the phone company confirms the caller’s number, which is common for US numbers. Otherwise the call rings.
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
        <p>
          <strong>Why it matters:</strong> send a hello, a reminder about an appointment, or the family news, and it
          waits on the tablet until your loved one plays it. They have no inbox to check and no notifications to notice.
        </p>
        <h3>Send one</h3>
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
        <h3>How they play</h3>
        <ul>
          <li>
            The clock shows <UI>Play 1 message</UI> while something is waiting. A key set to{" "}
            <UI>Play / stop messages</UI> plays them too. <UI>Stop</UI> stops one.
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
    title: "Messages that play when they’re there",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> your loved one doesn’t have to press anything. When the tablet notices
          someone in front of it, Porch says <Says>You have 2 new messages.</Says> and plays them.
        </p>
        <ul>
          <li>
            Turn on <Path steps={["Messages", "Play when someone is in front of the iPad"]} />. It uses the camera, and
            nothing is recorded.
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
            ["Default", "Off. When on, it plays from 8 AM until 9 PM."],
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
        <p>
          <strong>Why it matters:</strong> an unanswered call isn’t a dead end, in either direction.
        </p>
        <ul>
          <li>
            <strong>From the tablet:</strong> when the Porch app isn’t answered and the call doesn’t go on to their
            regular phone, Porch says <Says>[Name] didn’t answer. Please leave a message after the beep.</Says> Your
            loved one talks, presses 0 when they’re finished, and taps <UI>Send message</UI>, or <UI>Don’t send</UI>.
            It arrives in <UI>Messages with [Name]</UI> on the family member’s phone. If the call went on to their
            regular phone, that phone’s own voicemail takes the message instead.
          </li>
          <li>
            <strong>From a family phone:</strong> Porch asks <Says>Leave a message?</Says> Tap{" "}
            <UI>Leave a message</UI> to record one straight away, or <UI>Not now</UI>.
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
    title: "Their own Porch phone number",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> friends, neighbors and the doctor’s office can call your loved one from any
          phone, without the app. When your loved one’s call rings your regular phone, it shows this number, so you know
          it’s them.
        </p>
        <ul>
          <li>
            Every Porch gets its own US number during setup. It stays with your Porch.
          </li>
          <li>
            On a family phone, under <UI>[Name]’s Porch number</UI>, tap <UI>Add to Contacts</UI> or{" "}
            <UI>Share this number</UI>, which sends it by text with a contact card.
          </li>
          <li>
            Calls to it ring the tablet like any call, for the <UI>Ring before voicemail</UI> time. Then the caller can
            leave voicemail.
          </li>
          <li>
            Only people on the keypad and numbers you allow can get through. See the next part.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Set up during setup."],
            ["See it", <>At the top of caregiver mode, under <UI>Porch number</UI>, or on any family phone.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "blocking",
    title: "Unknown callers are blocked",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> phone numbers get passed around and dialed by robocallers. Your loved one only
          hears from people you know.
        </p>
        <ul>
          <li>
            These numbers can ring: every number saved on the keypad, numbers approved to drop in, and numbers you
            allow. Calls with a hidden number are always turned away.
          </li>
          <li>
            Turned-away calls are listed in <Path steps={["Calls", "Blocked numbers"]} />. Tap <UI>Allow</UI> to let a
            number through from now on.
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
            ["Change it", <><Path key="p" steps={["Calls", "Block unknown callers"]} />, on the tablet or a caregiver’s phone. Off, anyone with the number can ring.</>],
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
        <p>
          <strong>Why it matters:</strong> someone who misses your loved one can leave a voicemail, and a text is read
          aloud in their language. You screen anything from people you don’t know.
        </p>
        <ul>
          <li>
            <strong>Voicemail</strong> from a number on the keypad plays on the tablet like a family message. Voicemail
            from anyone else waits for a caregiver.
          </li>
          <li>
            <strong>Texts</strong> from numbers on the keypad, approved to drop in, or allowed are shown and read aloud
            on the tablet, translated into their language if needed. Pictures can’t be shown yet. Texts from anyone else
            wait for a caregiver.
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
            ["Default", "On. Voicemail and texts from numbers you don’t know wait for a caregiver’s OK."],
            ["Change it", <>There’s no separate switch. Turning off <UI>Allow family messages</UI> stops voicemail and texts too.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "three-way",
    title: "Bring someone else into the call",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> add a brother across the country, an old friend, or the bank when they need
          to speak with your loved one directly. Everyone is on one call, and your loved one doesn’t have to juggle
          anything.
        </p>
        <ol>
          <li>
            During a call with the tablet from your phone, once it’s connected, tap <UI>Add someone</UI>.
          </li>
          <li>
            Choose a family member, and Porch rings them into the call. Or, if you’re a caregiver, choose{" "}
            <UI>A phone number…</UI>, enter who you’re calling and their number, and tap{" "}
            <UI>Call and add to this call</UI>.
          </li>
          <li>
            Tap <UI>Hang up [their name]</UI> to let them go. If you hang up, a phone number you added is hung up
            too.
          </li>
        </ol>
        <Setting
          rows={[
            ["Default", "Anyone in the family can add a family member. Only caregivers can add a phone number."],
            ["Limits", "Phone numbers in the US and Canada, including toll-free numbers. The tablet can’t start one."],
          ]}
        />
      </>
    ),
  },
  {
    id: "abroad",
    title: "Family in other countries",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> family overseas can be one press away, just like family next door.
        </p>
        <ul>
          <li>Calls between the Porch apps work anywhere.</li>
          <li>
            To save a phone number outside the US on a key, start it with + and the country code. Porch checks it when
            you tap <UI>Save</UI>.
          </li>
          <li>
            If Porch says it can’t call numbers in that country yet, <Contact /> and I can turn that country on.
          </li>
          <li>
            Drop-ins from a regular phone abroad just ring, and three-way calls can only add US and Canadian numbers.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Porch apps work everywhere. Regular phones in the US and Canada can always be called."],
            ["Change it", "Other countries, on request."],
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
        <p>
          <strong>Why it matters:</strong> Porch shows its screens and speaks its announcements in the language your
          loved one grew up with, in a natural-sounding voice, around a clock that’s easy to read.
        </p>
        <ol>
          <li>
            On the tablet, open <Path steps={["Display & voice"]} />.
          </li>
          <li>
            <UI>Bedside language</UI>: English, Mandarin in traditional or simplified characters, Cantonese, Spanish,
            Tagalog or Korean.
          </li>
          <li>
            <UI>Announcement voice</UI>: a natural voice, or one of the tablet’s own. Tap{" "}
            <UI>Preview announcement</UI> to hear it.
          </li>
          <li>
            <UI>Clock</UI>: <UI>Dark</UI>, or <UI>Day &amp; night</UI>, which shows day and night and lets you set when
            each begins.
          </li>
          <li>
            Tap <UI>Save</UI>. Nothing changes until you do.
          </li>
        </ol>
        <p>
          The language also sets how Porch greets people who reach voicemail on the Porch number, and which language
          texts are translated into. Caregiver mode and the family apps stay in English.
        </p>
        <Setting
          rows={[
            ["Default", "English, a natural voice, and the Dark clock."],
            ["Change it", "Tablet only."],
            ["Natural voice off", <>Choose <UI>System default</UI> or one of the tablet’s own voices.</>],
            ["Android", <>If Porch says no voice is available for a language, add one in Android’s <UI>Settings</UI>, under <UI>Accessibility</UI>, <UI>Text-to-speech output</UI>.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "presence",
    title: "Seeing that someone’s at the tablet",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> at a glance, family can see that someone has been at the tablet recently. It’s
          reassuring, and it’s a good cue for when to call.
        </p>
        <ul>
          <li>
            Family phones show <UI>Someone is at the iPad</UI>, or <UI>Someone was at the iPad 12 minutes ago</UI>.
            Android says “tablet”.
          </li>
          <li>Touching the screen and pressing keys count.</li>
          <li>
            <UI>Check with the camera</UI> also lets the camera notice someone, about every 30 seconds. Nothing is
            recorded.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", "Sharing is on, from touches and key presses. The camera check is off."],
            ["Change it", <><Path key="p" steps={["Privacy", "Show family when someone is at the iPad"]} />, on the tablet or a caregiver’s phone. <UI>Check with the camera</UI> is on the tablet only.</>],
          ]}
        />
      </>
    ),
  },
  {
    id: "history",
    title: "Call history, and calls left open",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> see who’s been calling and whether calls were missed, and make sure a call
          nobody hung up doesn’t keep the tablet busy.
        </p>
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
            ["Default", "Ending silent calls is off. When on, it waits 2 minutes, and you can choose 1 to 30."],
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
          <strong>Why it matters:</strong> a familiar phone is easier than a touchscreen. Its keys call people, answer
          and hang up. The conversation itself comes through the tablet’s speaker, microphone and camera.
        </p>
        <ul>
          <li>Lift the receiver to use the keys. Lifting it alone doesn’t answer: press 0.</li>
          <li>Putting the receiver back hangs up.</li>
          <li>
            To check the phone again, open <Path steps={["This iPad", "Connect the phone"]} />. On Android it’s{" "}
            <UI>This tablet</UI>, which also has <UI>Retry phone connection</UI>.
          </li>
          <li>
            A USB number keypad works too: <UI>Connect the USB keypad</UI>, in the same place.
          </li>
        </ul>
        <Setting
          rows={[
            ["Default", <>On: putting the receiver back hangs up.</>],
            ["Change it", <><Path key="p" steps={["This iPad", "Hang up when the receiver is put back"]} />, tablet only. Turn it off if the receiver tends to get put down during calls they meant to keep.</>],
            ["Android", <>The phone switch is <UI>Use Cell2Jack phone keypad</UI> under <UI>This tablet</UI>. Setup turns it on.</>],
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
        <p>
          <strong>Why it matters:</strong> everyone who matters to your loved one can be on their Porch, and you decide
          what each person can do.
        </p>
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
          Invitations they haven’t used yet are listed as <UI>Invited</UI>, with <UI>Cancel</UI>.
        </p>
        <h3>Change what someone can do</h3>
        <p>Tap them under People or Family. Their page has:</p>
        <ul>
          <li>
            Their name and photo, as your loved one sees them. <UI>Use their own photo</UI> undoes a change.
          </li>
          <li>
            <UI>Audio drop-in</UI> and <UI>Video drop-in</UI>.
          </li>
          <li>
            <UI>Caregiver mode</UI>, to let them change settings from their phone with the PIN.
          </li>
          <li>
            <UI>Remove [Name]</UI>. They’ll need a new invitation to come back.
          </li>
        </ul>
        <p>
          To rename your loved one’s Porch, tap its name at the top of caregiver mode.
        </p>
        <Setting
          rows={[
            ["Default", "People you invite may drop in with audio and video, and aren’t caregivers. Your own phone from setup is a caregiver."],
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
        <p>
          <strong>Why it matters:</strong> the PIN keeps settings safe from accidental taps at the tablet, while letting
          the caregivers you choose make changes from anywhere.
        </p>
        <ul>
          <li>
            To change it, open <Path steps={["Caregivers & PIN", "Change caregiver PIN"]} /> on the tablet. Enter the
            current PIN, then the new one twice, and tap <UI>Save new PIN</UI>.
          </li>
          <li>
            Turn caregiver access on or off for each person in the same place, or on their page.
          </li>
          <li>After five wrong tries, caregiver mode waits 15 minutes.</li>
          <li>
            Forgot it? There’s no reset in the app yet, so <Contact />.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: "your-app",
    title: "Your own Porch app",
    body: (
      <>
        <p>
          <strong>Why it matters:</strong> your name and photo are how your loved one recognizes you on their screen.
        </p>
        <ul>
          <li>
            <strong>Name and photo:</strong> on an iPhone, tap your photo or the person icon in the top right corner. On
            Android, tap <UI>Your name and photo</UI>.
          </li>
          <li>
            <UI>Start video calls with my camera on</UI>: turn it off to start video calls with your camera off.
          </li>
          <li>
            <strong>More than one loved one?</strong> One phone can join up to four Porches, with{" "}
            <UI>Join another family</UI>.
          </li>
          <li>
            <strong>Leaving:</strong> on Android, tap <UI>Leave this family</UI>. On an iPhone, the leave button appears
            once you’re in two or more families. With only one, ask a caregiver to remove you.
          </li>
          <li>
            <strong>Ringing:</strong> allow Porch’s notifications and microphone, so calls ring even when Porch is
            closed. On Android, follow the <UI>Ring when Porch is closed</UI> card if it’s showing.
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
          <strong>A new tablet:</strong> <Contact />, and I’ll send you a link to move Porch to it. Your loved one’s
          Porch number and family stay the same. The keypad is kept on the old tablet, so you’ll set the keys up again.
        </li>
        <li>
          <strong>Turning the tablet into a family device,</strong> for calling the bedside instead:{" "}
          <Path steps={["This iPad", "Use this iPad as a family device"]} />. You can switch it back later from its
          Porch settings, with <UI>Use this iPad as the bedside Porch</UI>.
        </li>
      </ul>
    ),
  },
  {
    id: "coming",
    title: "Not available yet",
    body: (
      <>
        <p>These are planned. Until then, I can help with each of them.</p>
        <ul>
          <li>Resetting a forgotten caregiver PIN.</li>
          <li>Deleting a Porch, its number and everything in it.</li>
          <li>Backing up the keypad, so a new tablet gets it automatically.</li>
        </ul>
        <p>
          Something here not working the way it says, or a feature you wish Porch had? <Contact />.
        </p>
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
          Every feature, <em>and how to use it.</em>
        </>
      }
      lede={
        <p>
          What each part of Porch does for your family, what it does out of the box, and where to change it or turn it
          off. It covers the iPad, Android tablets, and family phones.
        </p>
      }
      aside={
        <>
          Setting up for the first time? Start with <Link href="/pilot/ios">the iPad and iPhone guide</Link> or{" "}
          <Link href="/pilot/android">the Android guide</Link>.
        </>
      }
      parts={parts}
    />
  );
}
