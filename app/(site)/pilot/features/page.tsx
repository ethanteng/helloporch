import Link from "next/link";
import { Contact, Defaults, Guide, guideMetadata, Path, Says, Screenshot, Setting, Tip, UI, type GuidePart } from "../_guide/parts";

export const metadata = guideMetadata(
  "Porch features and settings | HelloPorch",
  "Learn how Porch calls, messages and caregiver settings work on your loved one’s tablet and family phones.",
);

// Defaults come from household setup in lib/family/service.ts and from the apps' own settings.

const parts: GuidePart[] = [
  {
    id: "settings",
    title: "Open caregiver mode",
    body: (
      <>
        <p>
          <strong>Caregiver mode</strong> is where you change Porch’s settings. Open it using the six-digit
          PIN you chose during setup.
        </p>
        <ul>
          <li>
            <strong>On your loved one’s tablet:</strong> Tap the gear at the top right of the clock, enter
            your PIN and tap <UI>Open caregiver mode</UI>. Tap <UI>Back to clock</UI> when you’re done.
          </li>
          <li>
            <strong>On your phone:</strong> On iPhone, tap your photo or the person icon at the top right,
            then <UI>Caregiver mode</UI>. On Android, tap <UI>Caregiver mode</UI> below your loved one’s
            name. Enter your PIN. Tap <UI>Done</UI> to close it. It also locks automatically after 10 minutes
            of inactivity.
          </li>
        </ul>
        <Screenshot
          src="/pilot/screens/ipad-keypad.png"
          width={1600}
          height={1112}
          device="tablet"
          alt="Caregiver mode on the iPad. The menu on the left lists People, Calls, Drop-in, Messages, Display & voice, Privacy, Caregivers & PIN and This iPad, with People open on the right."
          caption="Caregiver mode on iPad. Choose a setting from the menu on the left."
        />
        <p>
          Some settings can only be changed on your loved one’s tablet. They’re marked <em>tablet only</em>
          in this guide. On your phone, these settings appear locked under <UI>On the bedside iPad</UI> or{" "}
          <UI>On the bedside tablet</UI>.
        </p>
        <p>
          In the instructions below, an Android tablet may show “tablet” where an iPad shows “iPad.”
        </p>
        <p>In buttons such as <UI>Send to [Name]</UI>, Porch shows your loved one’s name instead of [Name].</p>
        <Tip label="Return to the clock after changing settings">
          <p>
            Drop-in calls won’t connect while caregiver mode is open on the tablet. Tap{" "}
            <UI>Back to clock</UI> when you’re done.
          </p>
        </Tip>
      </>
    ),
  },
  {
    id: "defaults",
    title: "How Porch starts out",
    body: (
      <>
        <p>
          These are Porch’s starting settings. You can change them later. By default, people you
          invite are allowed to <a href="#drop-in">drop in</a> without your loved one answering.
          You can turn that off for each person.
        </p>
        <Defaults
          rows={[
            ["Drop-in", "On", <Path key="p" steps={["Drop-in", "Allow drop-ins"]} />],
            ["Who can drop in", "Everyone you invite, with audio and video", <>Each person’s page, or the invitation</>],
            ["Caregiver access for people you invite", "Off", <>Each person’s page</>],
            ["Calls from unknown numbers", "Blocked", <Path key="p" steps={["Calls", "Block unknown callers"]} />],
            ["How long calls ring", "45 seconds", <><Path steps={["Calls", "Ring before voicemail"]} />, tablet only</>],
            ["Try their regular phone after a missed app call", "After 20 seconds, if the key has a phone number", <><Path steps={["Calls", "Try their phone after"]} />, tablet only</>],
            ["Leave a message after an unanswered call", "Offered unless the call went to a regular phone", <><Path steps={["Calls", "Leave a message if no one answers"]} />, tablet only</>],
            ["End calls after silence", "On, after 2 minutes", <><Path steps={["Calls", "End calls after silence"]} />, tablet only</>],
            ["Family messages", "On", <Path key="p" steps={["Messages", "Allow family messages"]} />],
            ["Voicemail and texts from unknown numbers", "Held for a caregiver to review", <Path key="p" steps={["Messages", "Waiting messages"]} />],
            ["Play messages when someone is nearby", "On, from 8 AM until 9 PM", <><Path steps={["Messages", "Play when someone is in front of the iPad"]} />, tablet only</>],
            ["Show family when someone was at the tablet", "On, from touches and key presses", <Path key="p" steps={["Privacy", "Show family when someone is at the iPad"]} />],
            ["Check for someone using the camera", "On", <><Path steps={["Privacy", "Check with the camera"]} />, tablet only</>],
            ["Language", "English", <><Path steps={["Display & voice", "Bedside language"]} />, tablet only</>],
            ["Announcement voice", "Porch’s voice", <><Path steps={["Display & voice", "Announcement voice"]} />, tablet only</>],
            ["Clock", "Day & night", <><Path steps={["Display & voice", "Clock"]} />, tablet only</>],
            ["Keypad", "0 answers and hangs up, 9 turns video off and on, and the other keys are empty", <><Path steps={["People"]} />, tablet only</>],
            ["New keypad calls", "Start as video", <>The key’s <UI>Calls start as</UI>, tablet only</>],
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
          Once you’ve assigned people to the keypad, your loved one can lift the receiver and press
          their button to call. They can also tap <UI>Call someone</UI> on the tablet and choose a name.
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
            Under <UI>Their details</UI>, choose someone who has already joined using{" "}
            <UI>Choose from Family on Porch</UI>. Otherwise, enter their name or tap{" "}
            <UI>Choose from Contacts</UI>. If you invite them now with <UI>Invite them</UI> or later
            with <UI>Invite someone</UI>, use the same name as their key. Porch will then switch the key
            to their app when they join.
          </li>
          <li>
            Under <UI>Calls start as</UI>, choose video or audio. Add a photo under{" "}
            <UI>Photo &amp; button color</UI>.
          </li>
          <li>
            To call their regular phone if they miss an app call,{" "}
            <a href="#phone-fallback">add their phone number</a>. Then tap <UI>Save</UI>.
          </li>
        </ol>
        <p>
          To move someone to a different button, open <UI>People</UI>, tap their name, then{" "}
          <UI>Keypad key</UI>. Choose another key or <UI>Take off the keypad</UI>.
        </p>
        <p>
          Use the <Link href="/labels">phone button label maker</Link> to print photos and names for
          the physical buttons.
        </p>
        <h3>What else a key can do</h3>
        <ul>
          <li>
            <UI>Answer / decline / hang up</UI> lets the button answer a call, stop a drop-in before
            it connects or hang up. To decline a ringing call, tap <UI>Decline</UI> on the screen.
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
          If someone doesn’t answer in the Porch app, Porch can call their regular phone after a short
          wait. That second call is voice-only and shows your loved one’s Porch number.
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
            Use <UI>Add another number</UI> to save any other numbers they might call from. You can
            save up to five numbers per person, but Porch calls the primary number.
          </li>
          <li>
            Tap <UI>Save</UI>.
          </li>
        </ol>
        <p>
          If someone has only a regular phone number on their key, Porch calls it right away.
          If they don’t answer, their phone’s voicemail may take a message.
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
            If you’re allowed to <a href="#drop-in">drop in</a> and the clock is showing on the tablet,
            your call connects automatically.
          </li>
          <li>
            Otherwise, the tablet rings. Your loved one can tap <UI>Answer video call</UI>, or lift
            the receiver and press 0. To decline, tap <UI>Decline</UI>.
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
          A <strong>drop-in</strong> call connects without your loved one having to answer. Porch
          plays a chime, announces who’s calling and waits five seconds before connecting. Your loved one
          can stop it during that time.
        </p>
        <ul>
          <li>
            On your phone, tap <UI>Drop in with video</UI> or <UI>Drop in with audio</UI>.
            If you have drop-in permission, even your regular <UI>Video call</UI> and{" "}
            <UI>Audio call</UI> connect this way.
          </li>
          <li>
            Your loved one can stop it by tapping <UI>Don’t connect</UI> or pressing 0.
          </li>
          <li>Drop-ins only connect on their own while the clock is showing on the tablet.</li>
        </ul>
        <h3>Choose who may drop in</h3>
        <ul>
          <li>
            To pause all drop-in calls, turn off <Path steps={["Drop-in", "Allow drop-ins"]} />.
            Porch keeps each person’s permissions for when you turn it back on.
          </li>
          <li>
            To change access for one person, tap their name under <UI>Drop-in</UI> or <UI>People</UI>. Turn <UI>Audio drop-in</UI> or{" "}
            <UI>Video drop-in</UI> on or off.
          </li>
          <li>
            For someone new, choose their drop-in permissions when you invite them, using the{" "}
            <UI>Approve drop-in</UI> switches.
          </li>
        </ul>
        <h3>Drop in from a regular phone</h3>
        <p>
          To allow someone to drop in from a regular phone, open{" "}
          <Path steps={["Drop-in", "Add a phone number"]} /> and turn on <UI>Approve audio drop-in</UI>.
          The call connects automatically only if the phone company verifies their caller ID. Otherwise,
          the tablet rings.
        </p>
        <Setting
          rows={[
            ["Default", "On. Everyone you invite can drop in with audio or video, including your own phone from setup."],
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
            Choose <UI>Record a video</UI> or <UI>Record audio</UI>. A message can be up to two minutes long.
          </li>
          <li>
            Tap <UI>Play it back</UI> to check it, then <UI>Send to [Name]</UI>.
          </li>
        </ol>
        <p>
          Under <UI>Messages with [Name]</UI>, you can see whether a message has been played.
          You can also <UI>Unsend</UI> one that hasn’t been played yet.
        </p>
        <h3>Play messages</h3>
        <ul>
          <li>
            On the clock screen, tap <UI>Play 1 message</UI>, or press a phone button assigned to{" "}
            <UI>Play / stop messages</UI>. Tap <UI>Stop</UI> to end playback.
          </li>
          <li>
            Porch says who each message is from and when it was sent.
          </li>
          <li>Messages that aren’t played within a week are removed.</li>
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
            When <Path steps={["Messages", "Play when someone is in front of the iPad"]} /> is on,
            Porch checks whether someone is in front of the tablet. If so, it announces and plays
            waiting messages. It does not record video.
          </li>
          <li>
            Set the hours using <UI>Starting at</UI> and <UI>Until</UI>, so messages won’t play
            during the night.
          </li>
          <li>
            If your loved one taps <UI>Not now</UI> or <UI>Stop</UI>, Porch won’t try again
            for another 30 minutes.
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
            <strong>When your loved one calls someone:</strong> If nobody answers in Porch, the tablet
            asks them to speak after the beep. They press 0 when finished, then tap{" "}
            <UI>Send message</UI> or <UI>Don’t send</UI>. The message appears under{" "}
            <UI>Messages with [Name]</UI> on the family member’s phone. If Porch called
            a regular phone instead, that phone’s voicemail may answer.
          </li>
          <li>
            <strong>When you call your loved one:</strong> If they don’t answer, Porch asks{" "}
            <Says>Leave a message?</Says>. Tap <UI>Leave a message</UI> to record one or{" "}
            <UI>Not now</UI> to skip it.
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
            Porch gets its own US phone number during setup. Save it to your contacts so you
            recognize calls from your loved one.
          </li>
          <li>
            On a family phone, under <UI>[Name]’s Porch number</UI>, tap <UI>Add to Contacts</UI> or{" "}
            <UI>Share this number</UI>, which sends it by text with a contact card.
          </li>
          <li>
            People can call this number from a regular phone. The tablet rings, and if nobody
            answers, the caller may leave a voicemail.
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
            By default, Porch accepts calls from numbers on the keypad, numbers approved for drop-ins
            and numbers you’ve allowed. Calls with hidden numbers are blocked.
          </li>
          <li>
            To let a blocked number through, open <Path steps={["Calls", "Blocked numbers"]} /> and tap <UI>Allow</UI>{" "}
            next to the number.
          </li>
          <li>
            Allowed numbers are listed under <UI>Allowed</UI>, each with <UI>Remove</UI>.
          </li>
          <li>
            <UI>Clear this list</UI> clears the blocked-call list, but it doesn’t allow those
            callers through.
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
            <strong>Voicemail:</strong> Messages from numbers on the keypad play on the tablet
            like family messages. Other voicemail waits for a caregiver to approve it.
          </li>
          <li>
            <strong>Texts:</strong> Messages from numbers on the keypad, numbers approved for
            drop-ins or numbers you’ve allowed appear on the tablet. Porch can read them aloud
            and translate them. It only receives texts; it doesn’t send replies.
            Texts from other numbers wait for a caregiver to review.
          </li>
          <li>
            When something needs approval, a caregiver’s phone shows a notice such as{" "}
            <UI>1 phone voicemail needs your review</UI> or <UI>1 text needs your review</UI>.
          </li>
          <li>
            Open <Path steps={["Messages", "Waiting messages"]} /> to review them. For voicemail,
            tap <UI>Listen first</UI>. Then choose <UI>Let it play on Porch</UI>,
            <UI>Let it show on Porch</UI> or <UI>Remove</UI>, as appropriate.
          </li>
          <li>Unread texts are removed after a week.</li>
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
            Choose a family member to call. Caregivers can also choose <UI>A phone number…</UI>,
            enter a name and number, and tap <UI>Call and add to this call</UI>.
          </li>
          <li>
            To disconnect someone, tap <UI>Hang up [their name]</UI>. If you end your own call,
            anyone you added by regular phone number is disconnected too.
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
          <li>Porch-to-Porch calls work over the internet, including when family members are abroad.</li>
          <li>
            For a regular phone number outside the US, enter + followed by the country code and
            number. Porch checks it when you tap <UI>Save</UI>.
          </li>
          <li>
            If Porch says calling that country isn’t available yet, <Contact />. I can enable it.
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
            Under <UI>Bedside language</UI>, choose English, Mandarin (traditional or simplified
            characters), Cantonese, Spanish, Tagalog or Korean.
          </li>
          <li>
            Under <UI>Announcement voice</UI>, choose one of Porch’s voices (marked Natural)
            or a voice on the tablet. Tap <UI>Preview announcement</UI> to listen.
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
          The language you choose also controls the voicemail greeting and the language Porch
          translates incoming texts into. Caregiver mode and the apps on family phones stay in English.
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
    title: "See when someone is at the tablet",
    body: (
      <>
        <ul>
          <li>
            Family phones can show <UI>Someone is at the iPad</UI> or{" "}
            <UI>Someone was at the iPad 12 minutes ago</UI>. On Android, the message says
            “tablet” instead of “iPad”.
          </li>
          <li>The status updates when someone touches the screen or presses a phone button.</li>
          <li>
            With <UI>Check with the camera</UI> on, Porch also looks for someone in front of
            the tablet about every 30 seconds. It does not record video.
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
            <Path steps={["Calls", "Call history"]} /> shows the last 90 days of calls: who called,
            how long they talked and which calls were missed or declined. You can see it on the
            tablet or a caregiver’s phone.
          </li>
          <li>
            <Path steps={["Calls", "End calls after silence"]} /> ends a call after a period
            with no one speaking. Set the wait under <UI>After no one talks for</UI>.
          </li>
          <li>
            <Path steps={["Calls", "Test sounds"]} /> plays the ringtone and drop-in announcement
            so you can check the volume. This is on the tablet only.
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
          Your loved one uses the big-button phone to start, answer and end calls. They see
          and hear the caller on the tablet and speak into the tablet’s microphone, not the phone receiver.
        </p>
        <ul>
          <li>To answer, lift the receiver and press 0.</li>
          <li>Putting the receiver back hangs up.</li>
          <li>
            If the phone buttons stop working, you can run the connection test again under{" "}
            <Path steps={["This iPad", "Connect the phone"]} />. On Android, use <UI>This tablet</UI>
            instead of <UI>This iPad</UI>.
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
            Enter their name. Choose whether they can drop in with audio or video. Drop-in calls
            connect without your loved one answering, so turn these permissions off if calls should ring first.
            Give them <UI>Caregiver mode</UI> access only if they should be able to change settings.
          </li>
          <li>
            Tap <UI>Create invitation</UI> and send it by text or email. Each link works once
            and expires after 24 hours.
          </li>
        </ol>
        <p>
          To cancel an invitation before it’s used, find it under <UI>Invited</UI> and tap{" "}
          <UI>Cancel</UI>.
        </p>
        <h3>Change what someone can do</h3>
        <p>Open <UI>People</UI> on the tablet or <UI>Family</UI> on your phone, then tap their name.</p>
        <ul>
          <li>
            Change the name or photo your loved one sees. Tap <UI>Use their own photo</UI>
            to restore the photo they chose.
          </li>
          <li>
            Turn <UI>Audio drop-in</UI> and <UI>Video drop-in</UI> on or off.
          </li>
          <li>
            Turn on <UI>Caregiver mode</UI> if they need to change settings from their phone.
            They’ll also need the caregiver PIN.
          </li>
          <li>
            Tap <UI>Remove [Name]</UI> to remove them from the family. They’ll need
            another invitation to join again.
          </li>
        </ul>
        <p>
          To change the name shown for your loved one’s Porch, tap it at the top of caregiver mode.
        </p>
        <Setting
          rows={[
            ["Default", "Newly invited people can drop in with audio and video. Caregiver access is off for them, but on for the phone you added during setup."],
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
            To change the PIN, open <Path steps={["Caregivers & PIN", "Change caregiver PIN"]} />
            on the tablet. Enter your current PIN and the new one twice, then tap <UI>Save new PIN</UI>.
          </li>
          <li>
            You can also give or remove someone’s caregiver access here, or from their profile.
          </li>
          <li>After five incorrect PIN attempts, you’ll need to wait 15 minutes to try again.</li>
          <li>
            Forgot the PIN? <Contact /> and I can help reset it.
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
            <strong>Change your name or photo.</strong> On iPhone, tap your photo or the person
            icon at the top right. On Android, tap <UI>Your name and photo</UI>.
          </li>
          <li>
            To start video calls with your camera off, turn off <UI>Start video calls with my camera on</UI>.
          </li>
          <li>
            Tap <UI>Join another family</UI> to connect with another loved one. You can join
            up to four family groups on one phone.
          </li>
          <li>
            To leave a family on Android, tap <UI>Leave this family</UI>. On iPhone,
            you can leave from the app if you’ve joined at least two families. Otherwise,
            ask a caregiver to remove you.
          </li>
          <li>
            Allow notifications so calls can ring when Porch is closed, and microphone access
            so people can hear you. On Android, tap <UI>Ring when Porch is closed</UI> if shown.
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
          <strong>Move Porch to a new tablet.</strong> <Contact /> for a new setup link.
          Your loved one will keep their Porch number and family members, but you’ll need to
          set up the keypad buttons again.
        </li>
        <li>
          <strong>Use the tablet as a family device instead.</strong> On iPad, open{" "}
          <Path steps={["This iPad", "Use this iPad as a family device"]} />. On Android, open{" "}
          <Path steps={["This tablet", "Use this tablet as a family device"]} />. To switch an iPad
          back to your loved one’s Porch, use <UI>Use this iPad as the bedside Porch</UI> in its settings.
        </li>
      </ul>
    ),
  },
  {
    id: "coming",
    title: "Help during the pilot",
    body: (
      <>
        <p>During the pilot, <Contact /> if you need help with:</p>
        <ul>
          <li>A forgotten caregiver PIN.</li>
          <li>Deleting a Porch and its data, including the phone number.</li>
          <li>Setting up a replacement tablet or its keypad.</li>
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
Find the feature you need, from making calls and sending messages to changing settings on
          your loved one’s tablet or your own phone. You don’t need to follow these sections in order.
        </p>
      }
      aside={
        <>
          New to Porch? Start with the <Link href="/pilot/ios">iPad setup guide</Link> or{" "}
          <Link href="/pilot/android">Android tablet setup guide</Link>. Family members can use the{" "}
          <Link href="/pilot/phone">phone guide</Link>.
        </>
      }
      parts={parts}
    />
  );
}
