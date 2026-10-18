import { randomUUID } from "node:crypto";
import { displayPhoto, isCaregiver, mutate, requireValue, type Household, type Member, type Profile, type ProfilePhoto } from "./household.ts";
import type { MediaStore } from "./media.ts";
import { discardMedia } from "./messages.ts";
import type { FamilyStore } from "./store.ts";

// Family members choose their own name and photo; a caregiver can choose either one for them instead.
// Photos are JPEGs of at most 1 MB, the same limit as keypad photos. Each person's own photos and the
// caregiver's photos of them live in separate folders, so replacing one never deletes the other.
export const profileLimits = { photoBytes: 1_000_000, uploadSeconds: 600, downloadSeconds: 3600 };
export const profileActions = new Set(["setProfile", "profilePhotoUpload", "profilePhoto", "setMemberOverride", "overridePhotoUpload", "caregiverProfilePhoto"]);
const caregiverProfileActions = new Set(["setMemberOverride", "overridePhotoUpload", "caregiverProfilePhoto"]);
const uploadName = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}\.jpg$/;
const folder = (householdID: string, memberID: string, caregiver: boolean) => `profiles/${householdID}/${memberID}/${caregiver ? "caregiver" : "self"}/`;

export type ProfileContext = { store: FamilyStore; media: () => MediaStore; now: number; house: Household; me: Member; input: Record<string, unknown> };

/** A profile as devices see it: the photo's content ID, never where it is stored. */
export function publicProfile(profile: Profile | undefined) {
  return { ...(profile?.name ? { name: profile.name } : {}), ...(profile?.photo ? { photoID: profile.photo.id } : {}) };
}
/** Everything stored for this member's profile, deleted when they lose access. */
export function profileMedia(member: Member): string[] {
  return [member.profile?.photo, member.override?.photo].flatMap(photo => photo ? [photo.pathname] : []);
}

// undefined leaves a field as it is; null or an empty name clears it.
function nameChange(value: unknown): string | null | undefined {
  if (value === undefined || value === null) return value;
  requireValue(typeof value === "string" && value.trim().length <= 80, "Use a name with 80 characters or fewer.");
  return value.trim() || null;
}
async function photoChange(value: unknown, prefix: string, media: () => MediaStore): Promise<ProfilePhoto | null | undefined> {
  if (value === undefined || value === null) return value;
  const photo = value as Partial<ProfilePhoto>;
  requireValue(typeof value === "object" && typeof photo.id === "string" && /^[a-f0-9]{64}$/.test(photo.id) && typeof photo.pathname === "string" &&
    photo.pathname.startsWith(prefix) && uploadName.test(photo.pathname.slice(prefix.length)), "Choose the photo again.");
  const uploaded = await media().stat(photo.pathname);
  requireValue(uploaded, "The photo didn't finish uploading. Try again.", 409);
  requireValue(uploaded.contentType === "image/jpeg" && uploaded.size <= profileLimits.photoBytes, "Choose a photo smaller than 1 MB.");
  return { id: photo.id, pathname: photo.pathname };
}

export async function handleProfileAction(action: string, { store, media, now, house, me, input }: ProfileContext): Promise<object> {
  // Caregiver actions are PIN-checked before this point.
  const caregiver = caregiverProfileActions.has(action);
  if (!caregiver && action !== "profilePhoto") requireValue(me.role === "family", "Only family members have a profile.", 403);
  const memberID = caregiver || action === "profilePhoto" ? input.memberID ?? me.id : me.id;
  const member = house.members.find(m => m.id === memberID && m.role === "family" && !m.revoked);
  requireValue(member, "This family member was not found.", 404);
  if (action === "profilePhoto" || action === "caregiverProfilePhoto") {
    // The bedside shows everyone's photo; family members see their own, and caregivers' phones use the PIN.
    requireValue(caregiver || me.role === "bedside" || member.id === me.id, "Only a caregiver can see this photo.", 403);
    const photo = input.source === "self" ? member.profile?.photo : displayPhoto(member);
    requireValue(photo, "This person doesn't have a photo.", 404);
    const expiresAt = now + profileLimits.downloadSeconds;
    return { photo: { id: photo.id, url: await media().downloadURL(photo.pathname, expiresAt), expiresAt } };
  }
  const prefix = folder(house.id, member.id, caregiver);
  if (action === "profilePhotoUpload" || action === "overridePhotoUpload") {
    const size = input.sizeBytes;
    requireValue(typeof size === "number" && Number.isInteger(size) && size > 0, "Choose the photo again.");
    requireValue(size <= profileLimits.photoBytes, "Choose a photo smaller than 1 MB.", 413);
    const pathname = `${prefix}${randomUUID()}.jpg`;
    return { upload: await media().uploadTarget(pathname, "image/jpeg", size, now + profileLimits.uploadSeconds), pathname };
  }
  // setProfile and setMemberOverride: the photo was uploaded first, and is checked before anything changes.
  const name = nameChange(input.name);
  const photo = await photoChange(input.photo, prefix, media);
  const { result: replaced } = await mutate(store, house.id, current => {
    const target = current.members.find(m => m.id === member.id && m.role === "family" && !m.revoked);
    requireValue(target, "This family member was not found.", 404);
    // Rechecked inside the update: approval may have been withdrawn since the PIN check.
    if (caregiver) requireValue(current.members.some(m => m.id === me.id && !m.revoked && isCaregiver(m)), "Only an approved caregiver can change access.", 403);
    const key = caregiver ? "override" : "profile";
    const profile: Profile = { ...target[key] };
    const previous = profile.photo?.pathname;
    if (name === null) delete profile.name; else if (name !== undefined) profile.name = name;
    if (photo === null) delete profile.photo; else if (photo !== undefined) profile.photo = photo;
    if (profile.name || profile.photo) target[key] = profile; else delete target[key];
    return previous && previous !== profile.photo?.pathname ? [previous] : [];
  });
  try { await discardMedia(store, media, house.id, replaced, now); } catch { /* an unused photo is harmless */ }
  return {};
}
