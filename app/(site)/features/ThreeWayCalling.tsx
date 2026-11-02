import StoryVideo from "@/components/StoryVideo";
import { threeWayFilm } from "./clips";
import featureStyles from "./features.module.css";
import styles from "./three-way/three-way.module.css";

// 3-way calling: the film beside the copy, a full row at the end of the Calling tab.
export default function ThreeWayCalling() {
  return (
    <article id={threeWayFilm.id} className={styles.entry} aria-labelledby="three-way-calling-title">
      <StoryVideo
        src={threeWayFilm.src}
        poster={threeWayFilm.poster}
        title="3-way calling: adding the bank to a Porch call with Mom"
        width={1080}
        height={1920}
        className={`${featureStyles.player} ${styles.film}`}
      />
      <div className={`${featureStyles.clipCopy} ${styles.copy}`}>
        <span className={styles.label}>3-way calling</span>
        <h2 id="three-way-calling-title">{threeWayFilm.title}</h2>
        <p>{threeWayFilm.description}</p>
      </div>
    </article>
  );
}
