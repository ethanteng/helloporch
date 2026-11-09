import Link from "next/link";
import PorchLogo from "@/components/PorchLogo";
import { pageMetadata } from "@/lib/site-metadata";
import LabelMaker from "./LabelMaker";
import styles from "./labels.module.css";

export const metadata = pageMetadata({
  path: "/labels",
  title: "Phone Button Label Maker | HelloPorch",
  description: "Make printable photo and name labels for your Porch phone. Choose your button size and download a print-ready PDF.",
  image: { url: "/og/pilot.jpg", alt: "A Porch tablet and big-button phone" },
});

export default function LabelsPage() {
  return (
    <div className={styles.shell}>
      <header className={styles.header}>
        <div className={styles.headerInner}>
          <Link className="logo" href="/" aria-label="HelloPorch home"><PorchLogo /></Link>
          <Link href="/pilot" className={styles.back}>Porch pilot <span aria-hidden="true">↗</span></Link>
        </div>
      </header>
      <main className={styles.main}>
        <div className={styles.intro}>
          <span className={styles.kicker}>Family setup tool</span>
          <h1>Make phone <em>button labels.</em></h1>
          <p>Put familiar faces on your loved one’s Porch phone. Add your contacts, measure the buttons, and download a sheet to print.</p>
        </div>
        <LabelMaker />
      </main>
    </div>
  );
}
