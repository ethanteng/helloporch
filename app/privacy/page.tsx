import type { Metadata } from "next";
import SiteNav from "@/components/SiteNav";
import SiteFooter from "@/components/SiteFooter";
import styles from "./privacy.module.css";

export const metadata: Metadata = {
  title: "Privacy Policy | HelloPorch",
  description:
    "What the Porch app and the HelloPorch website collect, why, who helps us run Porch, how long we keep information, and how to have it deleted.",
};

const updated = "October 27, 2026";
// Where privacy questions and deletion requests go.
const contact = "privacy@helloporch.store";

const sections = [
  ["collect", "What we collect"],
  ["device", "What stays on your device"],
  ["use", "How we use it"],
  ["share", "Who we share it with"],
  ["keep", "How long we keep it"],
  ["security", "How we protect it"],
  ["choices", "Your choices"],
  ["caregivers", "Setting up Porch for someone else"],
  ["children", "Children"],
  ["changes", "Changes to this policy"],
  ["contact", "Contact us"],
] as const;

// Each provider, what it does for Porch, and what it receives to do it.
const providers: [name: string, role: string, receives: string][] = [
  ["LiveKit", "Carries live call audio and video between devices, and connects Porch calls to the phone network.", "Call audio and video as it happens, device and call identifiers, and the phone numbers on phone calls."],
  ["Twilio", "Phone service for a household’s Porch number, for calling a regular phone, and for adding a phone number to a call.", "Phone numbers, call audio as it happens, and voicemail recordings. We delete Twilio’s copy of each recording once we’ve saved it."],
  ["Vercel", "Hosts the website and our server, and keeps messages, photos and announcement audio in private storage.", "Everything our server handles, including request logs with IP addresses."],
  ["Upstash", "Database for household details, settings and the list of waiting messages.", "The household details described above."],
  ["Apple", "Delivers call and message notifications through the Apple Push Notification service, and runs TestFlight.", "Notification tokens, the caller’s name and call type for an incoming call, and a message sender’s name and length."],
  ["ElevenLabs", "Turns short announcements into natural speech, when a household uses a natural voice.", "Only the sentence to be spoken, which may include a family member’s name."],
  ["MailerLite", "Sends waitlist emails.", "Your email address and your waitlist answer."],
  ["Google", "Google Analytics counts visits to the website, so we can see which pages help people. It isn’t used in the Porch app.", "The pages you visit, the site that sent you, browser and device details, and your IP address, which it uses to estimate your general location."],
];

const retention: [what: string, howLong: string][] = [
  ["Messages waiting for your loved one", "Until they’re played. Deleted after 7 days if nobody plays them."],
  ["Played messages", "Kept 90 days so they can be replayed, then deleted."],
  ["Messages sent from your loved one’s iPad to family", "90 days from when they were left."],
  ["Unsent or removed messages", "Deleted right away."],
  ["Voicemail from phone callers", "The same as other messages. Twilio’s copy is deleted as soon as we’ve saved it."],
  ["Someone who leaves or is removed", "Their profile, photos, notification tokens and messages are deleted. We keep a small record that their device was removed, so it can’t reconnect."],
  ["Photos that are never saved", "Deleted shortly after the upload expires."],
  ["Blocked callers", "Up to the 30 most recent numbers, until a caregiver clears the list."],
  ["When someone was last at the iPad", "Only the most recent time, which replaces the one before."],
  ["Call history", "The 100 most recent calls, for up to 90 days, including calls with someone who was later removed."],
  ["Natural-voice announcements", "Kept so each sentence is made only once, until the household is deleted."],
  ["Household details", "While your household uses Porch. When you ask us to delete it, we delete its details, photos, messages and recordings within 30 days."],
  ["Waitlist email", "Until you unsubscribe or ask us to remove it."],
  ["Website analytics", "Up to 14 months in Google Analytics, then deleted."],
  ["Website and server request logs", "A short time, for security and troubleshooting."],
];

export default function PrivacyPage() {
  return (
    <div className={`page ${styles.page}`}>
      <a href="#policy" className={styles.skip}>Skip to the policy</a>
      <SiteNav joinHref="/#join" />

      <main id="policy">
        <header className={styles.hero}>
          <div className="hero__badge">Privacy policy</div>
          <h1 className={styles.title}>
            What Porch keeps, <em>and why.</em>
          </h1>
          <p className={styles.lede}>
            Porch connects someone at home with the people they love. This policy explains what information that
            takes, who helps us carry it, and how long we keep it. It covers the HelloPorch website and the Porch
            app for iPhone and iPad.
          </p>
          <p className={styles.updated}>Last updated {updated}</p>
        </header>

        <section className={styles.summary} aria-labelledby="summary-title">
          <h2 id="summary-title">The short version</h2>
          <ul>
            <li>We don’t sell your information, show ads, or track you across other apps and websites.</li>
            <li>Calls go live between devices and aren’t recorded. Only messages and voicemail that someone chooses to leave are saved.</li>
            <li>Unplayed messages are deleted after 7 days, and played ones after 90 days.</li>
            <li>When Porch notices someone in front of the iPad, detection happens on the device. No image leaves it. Family see only when someone was last there.</li>
            <li>A few service providers help us run calls, phone service, storage, notifications and website analytics. They get only what they need.</li>
            <li>
              Email <a href={`mailto:${contact}`}>{contact}</a> any time to see or delete your family’s information.
            </li>
          </ul>
        </section>

        <nav className={styles.contents} aria-labelledby="contents-title">
          <h2 id="contents-title">Contents</h2>
          <ol>
            {sections.map(([id, title]) => (
              <li key={id}>
                <a href={`#${id}`}>{title}</a>
              </li>
            ))}
          </ol>
        </nav>

        <div className={styles.body}>
          <section id="collect" aria-labelledby="collect-title">
            <h2 id="collect-title">What we collect</h2>

            <h3>On the website</h3>
            <p>
              If you join the waitlist, we collect your email address and, if you answer, who would use Porch (for
              example, “My mom”). We use it to email you about Porch.
            </p>
            <p>
              Like any website, our hosting provider receives your IP address and browser details when you visit, and
              keeps request logs for a short time. Our social media icons are plain links, and those sites have their
              own policies.
            </p>
            <p>
              The website uses Google Analytics to count visits and see which pages are useful. It sets cookies in your
              browser and tells Google which pages you visit, the site that sent you, and your browser and device. We
              use it only to understand the website, not for advertising, and the website doesn’t use advertising
              cookies.
            </p>

            <h3>In the Porch app</h3>
            <p>
              Porch has no usernames or passwords. A caregiver sets up a household with a private invitation, chooses a
              six-digit caregiver PIN, and invites family members. To make that work, our server keeps:
            </p>
            <ul>
              <li>
                <strong>Household details.</strong> The household’s name, the name used for your loved one’s iPad,
                each person’s name as it’s entered, who is a caregiver, and the settings you choose, such as drop-in
                permissions, ring time, and the language and announcement voice on your loved one’s iPad.
              </li>
              <li>
                <strong>Profile photos.</strong> A photo each person adds for themselves, or that a caregiver adds for
                them, if you choose to.
              </li>
              <li>
                <strong>Device sign-in details.</strong> A random identifier for each paired device and a secret that
                proves it belongs to your household. We store only a scrambled (hashed) form of that secret and of the
                caregiver PIN, never the PIN itself.
              </li>
              <li>
                <strong>Availability.</strong> When each device last checked in and whether it’s ready for calls, so
                Porch can show who is reachable.
              </li>
              <li>
                <strong>When someone was last at the iPad.</strong> The last time someone pressed a key or touched your
                loved one’s iPad and, if a caregiver turns it on, the last time its camera saw a face close by. We keep
                only the latest time. Family members see “Someone is at the iPad” or how long ago someone was, so they
                know whether to call. It doesn’t say who it was or how Porch noticed.
              </li>
              <li>
                <strong>Notification tokens.</strong> Addresses from Apple that let us ring a family phone or tell it a
                message has arrived.
              </li>
              <li>
                <strong>Phone numbers.</strong> Numbers saved on the Porch keypad or for calling a regular phone,
                numbers a caregiver approves to call or drop in, and numbers a caregiver adds to a call, with the label
                they give it.
              </li>
              <li>
                <strong>Call history.</strong> For each call to or from your loved one’s iPad: who it was with (their
                name, or the phone number for a regular phone), voice or video, when it started, whether it was
                answered, missed or declined, and how long it lasted. Caregivers can see it with the caregiver PIN. We
                don’t record what was said.
              </li>
              <li>
                <strong>Messages.</strong> Audio and video messages that family members record for each other,
                including on your loved one’s iPad, with who sent them, when, and whether they’ve been played.
              </li>
            </ul>
            <p>Call audio and video travel live between devices through our calling provider. We don’t record calls.</p>

            <h3>When someone calls a Porch number</h3>
            <p>
              A household can have its own phone number that any phone can call. When someone calls it, we receive the
              caller’s phone number, unless it’s withheld, and whether their phone company verified it. If nobody
              answers and the caller leaves voicemail, we keep the recording and their number. A caregiver reviews it
              before it plays, unless it’s a verified call from a number on the keypad. If a caregiver blocks unknown
              callers, we keep a list of recently blocked numbers, with when and how often they called, so the
              caregiver can review them.
            </p>

            <h3>If you join the pilot</h3>
            <p>
              Pilot families send us the Apple Account email address for each device, so Apple can send it a
              TestFlight invitation. We use those addresses only for the pilot. TestFlight may also share with us
              information such as your name, the version you installed, and any feedback or crash reports, according
              to your TestFlight settings and Apple’s privacy policy.
            </p>
          </section>

          <section id="device" aria-labelledby="device-title">
            <h2 id="device-title">What stays on your device</h2>
            <ul>
              <li>
                <strong>Noticing someone in front of the iPad.</strong> If a caregiver turns this on, your loved one’s
                iPad uses its camera to notice that a face is in view, so it can start waiting messages or let family
                know someone is there. This happens on the iPad. It doesn’t recognize who the person is, and no image is
                saved or sent anywhere. For family, only the time it last saw someone is sent.
              </li>
              <li>
                <strong>Contacts.</strong> When you pick someone from your contacts, Porch receives only that
                person’s name and phone numbers. It never reads your whole address book.
              </li>
              <li>
                <strong>Photos.</strong> When you choose a photo, Porch receives only that photo.
              </li>
              <li>
                <strong>Keypad and display settings.</strong> Contact buttons, photos on the keypad and display
                preferences stay on the device. The phone numbers on the Porch keypad are also sent to our server,
                so calls from those numbers are recognized.
              </li>
              <li>
                <strong>Built-in voices.</strong> When a household uses the iPad’s built-in voice, announcements are
                spoken on the iPad and nothing is sent to a speech service.
              </li>
            </ul>
          </section>

          <section id="use" aria-labelledby="use-title">
            <h2 id="use-title">How we use it</h2>
            <ul>
              <li>
                To run Porch: pair devices, ring and connect calls, deliver messages and voicemail, send notifications,
                place and receive phone calls, and speak announcements.
              </li>
              <li>
                To keep it safe: check that requests come from your household’s devices, enforce caregiver permissions,
                and limit misuse, for example with caps on messages and phone calls.
              </li>
              <li>To find and fix problems, and to make Porch better.</li>
              <li>To contact you about the waitlist, the pilot, or important changes to Porch.</li>
            </ul>
            <p>
              We don’t use your information for advertising, we don’t sell it, and we don’t share it for anyone
              else’s marketing. We don’t use your calls, messages or photos to train AI models.
            </p>
          </section>

          <section id="share" aria-labelledby="share-title">
            <h2 id="share-title">Who we share it with</h2>

            <h3>People in your household</h3>
            <p>
              People in a household see each other’s names, photos and whether they’re available. A message goes to
              the person it’s for, and a message for your loved one can be heard by whoever is near their iPad.
              Caregivers can see household settings and approved numbers, and can review messages and voicemail
              waiting for your loved one.
              When Porch calls a regular phone, the person who answers sees a Porch phone number as the caller ID.
            </p>

            <h3>Service providers</h3>
            <p>
              We use these companies to run Porch. They handle information on our behalf, to provide their service to
              us. We choose providers whose terms limit them to that and require them to protect information at least
              as well as this policy describes.
            </p>
            <dl className={styles.providers}>
              {providers.map(([name, role, receives]) => (
                <div key={name}>
                  <dt>{name}</dt>
                  <dd>{role}</dd>
                  <dd className={styles.receives}>
                    <span>Receives:</span> {receives}
                  </dd>
                </div>
              ))}
            </dl>

            <h3>When the law requires it</h3>
            <p>
              We may disclose information if the law requires it, to protect someone’s safety, or to protect Porch
              from fraud or abuse. If Porch ever becomes part of another company, your information would stay
              protected by this policy, and we’d tell you before it was used in a different way.
            </p>
          </section>

          <section id="keep" aria-labelledby="keep-title">
            <h2 id="keep-title">How long we keep it</h2>
            <dl className={styles.retention}>
              {retention.map(([what, howLong]) => (
                <div key={what}>
                  <dt>{what}</dt>
                  <dd>{howLong}</dd>
                </div>
              ))}
            </dl>
          </section>

          <section id="security" aria-labelledby="security-title">
            <h2 id="security-title">How we protect it</h2>
            <p>
              The app, the website and our server talk over encrypted connections. Call audio and video are encrypted
              on the way to and from our calling provider, but calls aren’t end-to-end encrypted: the provider’s
              servers handle them in order to route them. Calls to and from regular phones also travel over the
              telephone network.
            </p>
            <p>
              Messages and photos are kept in private storage, which devices reach only through links that expire
              within an hour. Device secrets and the caregiver PIN are stored hashed. No system is perfectly secure,
              but we work to protect your information, and we’ll tell you as the law requires if a breach affects it.
            </p>
          </section>

          <section id="choices" aria-labelledby="choices-title">
            <h2 id="choices-title">Your choices</h2>
            <ul>
              <li>
                <strong>Camera and microphone.</strong> Turn access on or off in your iPhone or iPad’s Settings. Voice
                calls never turn on the camera.
              </li>
              <li>
                <strong>Noticing someone in front of the iPad</strong> is off unless a caregiver turns it on, separately
                for starting messages and for telling family.
              </li>
              <li>
                <strong>Drop-in</strong> works only for people a caregiver approves, and can be turned off at any time.
              </li>
              <li>
                <strong>Messages and voicemail</strong> can be turned off by a caregiver.
              </li>
              <li>
                <strong>Announcements</strong> can use the iPad’s built-in voice, so nothing is sent to a speech
                service.
              </li>
              <li>
                <strong>Leaving.</strong> A family member can leave a household in the app, and a caregiver can remove
                anyone.
              </li>
              <li>
                <strong>Seeing or deleting your information.</strong> Email us to get a copy of your information, to
                correct it, or to delete a whole household.
              </li>
              <li>
                <strong>Waitlist emails.</strong> Use the unsubscribe link in any email.
              </li>
              <li>
                <strong>Website analytics.</strong> Block cookies for helloporch.store in your browser, or install
                Google’s <a href="https://tools.google.com/dlpage/gaoptout">Analytics opt-out add-on</a>.
              </li>
            </ul>
            <p>
              Depending on where you live, you may have rights to access, correct, delete or get a copy of your
              information, and to object to some uses. We honor these requests wherever you live, and we won’t treat
              you differently for making one. We don’t sell or share personal information as California law defines
              those terms.
            </p>
          </section>

          <section id="caregivers" aria-labelledby="caregivers-title">
            <h2 id="caregivers-title">Setting up Porch for someone else</h2>
            <p>
              Porch is often set up by a caregiver for a parent or loved one who doesn’t manage technology
              themselves. If you set up Porch for someone, please make sure you’re entitled to make these choices for
              them, and explain Porch to them in a way they can understand, including that people they approve can
              drop in. When you add other people’s phone numbers or photos, please add only what they’d be comfortable
              with.
            </p>
            <p>
              Porch isn’t an emergency, medical or monitoring service. In an emergency, call 911 or your local
              emergency number.
            </p>
          </section>

          <section id="children" aria-labelledby="children-title">
            <h2 id="children-title">Children</h2>
            <p>
              Porch isn’t made for children, and we don’t knowingly collect information from children under 13.
              Children can of course join a family call on a parent’s device. If you think a child has given us
              information, contact us and we’ll delete it.
            </p>
          </section>

          <section id="changes" aria-labelledby="changes-title">
            <h2 id="changes-title">Changes to this policy</h2>
            <p>
              When we change this policy, we’ll update the date at the top. If a change affects how we use
              information we already have, we’ll tell you in the app or by email before it takes effect. Porch is run
              from the United States, and our providers may process information wherever they operate.
            </p>
          </section>

          <section id="contact" aria-labelledby="contact-title">
            <h2 id="contact-title">Contact us</h2>
            <p>
              Questions, or a request to see or delete your information? Email{" "}
              <a href={`mailto:${contact}`}>{contact}</a>. We’ll reply within 30 days.
            </p>
          </section>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
}
