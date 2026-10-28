import StoryVideo from "@/components/StoryVideo";
import { AddPhoneForm, CallScreen, Phone, Porch, Sheet } from "./three-way/Screens";
import { threeWayPeople } from "./three-way/people";
import featureStyles from "./features.module.css";
import styles from "./three-way/three-way.module.css";

// The film is rendered from the screens below by scripts/render-three-way-film.mjs.
const FILM = "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/3-way%20calling%20compressed.mp4";

// 3-way calling: a short film, then the app's own screens step by step: adding the bank on a family phone, the
// call once the bank answers, and what Mom's Porch shows.
export default function ThreeWayCalling() {
  const { mom, caller } = threeWayPeople();
  return (
    <article id="three-way-calling" className={styles.entry} aria-labelledby="three-way-calling-title">
      <div className={styles.intro}>
        <StoryVideo
          src={FILM}
          poster="/features/three-way-calling.jpg"
          title="3-way calling: adding the bank to a Porch call with Mom"
          width={1080}
          height={1920}
          className={`${featureStyles.player} ${styles.film}`}
        />
        <div className={`${featureStyles.clipCopy} ${styles.copy}`}>
          <span className={styles.label}>3-way calling</span>
          <h2 id="three-way-calling-title">When the bank needs them on the line, too.</h2>
          <p>
            You’re sorting out their account, and the bank won’t go on until they say it’s OK themselves. Call them on
            Porch, tap Add someone, and bring the bank into the same call. They hear everything and answer in their own
            voice, while you work the phone menu and sit through the hold music. When you hang up, the bank hangs up
            too, so they’re never left alone with a caller they didn’t choose. Family can join the same way, with video.
          </p>
        </div>
      </div>
      <div className={styles.shots}>
        <figure className={styles.shot}>
          <Phone label="Your phone on a Porch call with Mom, adding a phone: Bank, (800) 555-0199, then Call and add to this call." light>
            <CallScreen device="phone" title={mom.name} status={["Video call connected"]} remote={mom} self={caller}>
              <Sheet page>
                <AddPhoneForm name="Bank" number="(800) 555-0199" />
              </Sheet>
            </CallScreen>
          </Phone>
          <figcaption>
            <span className={styles.step}>1</span>
            <span>On a Porch call with Mom, tap Add someone and enter the bank’s number.</span>
          </figcaption>
        </figure>
        <figure className={styles.shot}>
          <Phone label="Your phone on the call with Mom, with Bank is on the call, Keypad and Hang up Bank.">
            <CallScreen
              device="phone"
              title={mom.name}
              status={["Video call connected"]}
              remote={mom}
              self={caller}
              guest={{ name: "Bank", answered: true }}
            />
          </Phone>
          <figcaption>
            <span className={styles.step}>2</span>
            <span>Everyone hears it ring. Use Keypad for the bank’s menu.</span>
          </figcaption>
        </figure>
        <figure className={styles.shot}>
          <Porch label={`Mom’s Porch on the call with ${caller.name}, saying Bank joined the call.`}>
            <CallScreen
              device="porch"
              title={caller.name}
              status={["Video call connected", "Bank joined the call"]}
              remote={caller}
              self={mom}
            />
          </Porch>
          <figcaption>
            <span className={styles.step}>3</span>
            <span>Mom sees you and hears the bank. Her screen says who joined, never the number.</span>
          </figcaption>
        </figure>
      </div>
    </article>
  );
}
