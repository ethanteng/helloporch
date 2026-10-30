import { notFound } from "next/navigation";
import Film from "../Film";
import { threeWayPeople } from "../people";

// The 3-way calling film, for recording with scripts/render-three-way-film.mjs while `npm run dev` is running.
// It isn't part of the site, so production serves a 404.
export default function ThreeWayFilmPage() {
  if (process.env.NODE_ENV === "production") notFound();
  return <Film people={threeWayPeople()} />;
}
