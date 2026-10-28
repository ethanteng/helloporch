import StoryVideo from "@/components/StoryVideo";
import featureStyles from "./features.module.css";
import styles from "./three-way/three-way.module.css";

// A film of the app's own 3-way calling screens, rendered by scripts/render-three-way-film.mjs.
const FILM = "https://lazmh5osa7q134vr.public.blob.vercel-storage.com/3-way%20calling%20compressed.mp4";

// 3-way calling: the film beside the copy, a full row at the end of the Calling tab.
export default function ThreeWayCalling() {
  return (
    <article id="three-way-calling" className={styles.entry} aria-labelledby="three-way-calling-title">
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
          voice, while you work the phone menu and sit through the hold music. When you hang up, the bank hangs up too,
          so they’re never left alone with a caller they didn’t choose. Family can join the same way, with video.
        </p>
      </div>
    </article>
  );
}
