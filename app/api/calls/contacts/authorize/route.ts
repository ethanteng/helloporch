import { authorizeContact } from "../../../../../lib/calls/contacts.ts";

export const runtime = "nodejs";
export const POST = (request: Request) => authorizeContact(request);
