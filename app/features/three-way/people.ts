import { existsSync } from "node:fs";
import { join } from "node:path";
import type { Person } from "./Screens";

// The people in the 3-way calling film. A portrait photo at public/features/three-way/mom.jpg or ethan.jpg,
// framed like a video call, replaces that person's placeholder.
export function threeWayPeople() {
  return { mom: person("Mom", "mom.jpg"), caller: person("Ethan", "ethan.jpg"), family: "David" };
}

export type ThreeWayPeople = ReturnType<typeof threeWayPeople>;

function person(name: string, file: string): Person {
  const photo = `/features/three-way/${file}`;
  return existsSync(join(process.cwd(), "public", photo)) ? { name, photo } : { name };
}
