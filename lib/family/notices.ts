import { bedsideDevice, displayName, displayPhone, mutate, phoneDropIn, type Call, type Household, type Member } from "./household.ts";
import { forgetRegistration, sendNoticePush, type CaregiverNotice, type PushResult, type VoIPRegistration } from "./push.ts";
import type { FamilyStore } from "./store.ts";
import { phoneNoticeAfter, roughly, type PhoneNotice } from "./bedside-phone.ts";

/** Notices to caregivers' phones while every call drops in (see `everyCall` in household.ts). */
export type NoticeDependencies = { sendNotice?: (device: VoIPRegistration, notice: CaregiverNotice) => Promise<PushResult> };
type Notice = { title: string; body: string } & ({ type: "everyCall" } | { type: "callNotice"; callID: string } | { type: "phone"; state: "out" | "back" });

function bedsideName(house: Household) {
  const bedside = house.members.find(m => m.role === "bedside" && !m.revoked);
  return bedside ? displayName(bedside) : house.name;
}
/** Family members with caregiver access whose phones can show a notice. */
function caregivers(house: Household) {
  return house.members.filter(m => m.role === "family" && !m.revoked && m.caregiver && m.alerts);
}
async function send(store: FamilyStore, house: Household, recipients: Member[], notice: Notice, dependencies: NoticeDependencies) {
  await Promise.all(recipients.map(async recipient => {
    const registration = recipient.alerts!;
    let result: PushResult;
    try { result = await (dependencies.sendNotice ?? sendNoticePush)(registration, { ...notice, recipientID: recipient.id }); }
    catch { return; }
    if (result.invalidToken) await mutate(store, house.id, current => {
      const member = current.members.find(m => m.id === recipient.id);
      if (member) forgetRegistration(member, registration);
    });
  }));
}

/** Tells the other caregivers' phones that every call was turned on or off, and by whom. The person who changed it
 * already knows, and the bedside shows it in caregiver mode. */
export async function noticeEveryCall(store: FamilyStore, house: Household, by: Member, on: boolean, dependencies: NoticeDependencies) {
  const name = bedsideName(house);
  const title = on ? `Every call drops in on ${name}` : `Every call is off for ${name}`;
  const body = by.role === "bedside" ? `Turned ${on ? "on" : "off"} at ${name}’s ${bedsideDevice(house)}.` : `${displayName(by)} turned it ${on ? "on" : "off"}.`;
  await send(store, house, caregivers(house).filter(m => m.id !== by.id), { type: "everyCall", title, body }, dependencies);
}

/** Who a phone call that came in while every call dropped in is from, as caregivers see it: an approved number's name,
 * or its number, or that the number was hidden. */
export function callTitle(house: Household, call: Call): string {
  const number = call.phone?.callerNumber;
  if (!number) return "Hidden number";
  const approved = call.everyCall?.verified ? phoneDropIn(house, number)?.name ?? call.peerName : undefined;
  return approved ?? displayPhone(number);
}
/** Tells every caregiver's phone that a phone call came in while every call drops in, so they can end it. A caller ID
 * the carrier didn't verify can be faked, so it's never given a name. */
export async function noticeCall(store: FamilyStore, house: Household, call: Call, dependencies: NoticeDependencies) {
  const name = bedsideName(house), number = call.phone?.callerNumber;
  const title = call.kind === "dropIn" ? `Dropping in on ${name}` : `Calling ${name}`;
  let body: string;
  if (!number) body = "Hidden number";
  else if (!call.everyCall?.verified) body = `${displayPhone(number)} · Not verified`;
  else {
    const approved = phoneDropIn(house, number)?.name ?? call.peerName;
    body = approved ? `${approved} · ${displayPhone(number)}`
      : house.keypadNumbers?.includes(number) ? `${displayPhone(number)} · On ${name}’s keypad` : `${displayPhone(number)} · Unknown number`;
  }
  await send(store, house, caregivers(house), { type: "callNotice", callID: call.id, title, body }, dependencies);
}

/** Tells caregivers the bedside's desk phone has been out for `phoneNoticeAfter`, or, only those who were told, that it's
 * back. Everything else on Porch still works on the touchscreen, so it says so. */
export async function noticePhone(store: FamilyStore, house: Household, notice: PhoneNotice, dependencies: NoticeDependencies) {
  const name = bedsideName(house);
  if (notice.state === "out") {
    const told = new Set(house.bedsidePhone?.notified ?? []);
    await send(store, house, caregivers(house).filter(m => told.has(m.id)), { type: "phone", state: "out",
      title: `${name}’s phone isn’t connected`, body: `Not connected for ${roughly(phoneNoticeAfter)}. The touchscreen still works.` }, dependencies);
    return;
  }
  const to = new Set(notice.to);
  await send(store, house, caregivers(house).filter(m => to.has(m.id)), { type: "phone", state: "back",
    title: `${name}’s phone is connected again`, body: `Back after ${roughly(notice.outFor)}.` }, dependencies);
}
