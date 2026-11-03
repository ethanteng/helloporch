import { initBotId } from "botid/client/core";

// BotID adds its proof that a person in a real browser sent these requests, and the routes check it with checkBotId()
// (lib/signup-guard.ts). The admin host has no sign-up forms, and Proxy sends all of its paths to the admin page,
// including the ones BotID's script loads from.
if (!location.hostname.startsWith("admin.")) {
  initBotId({
    protect: [
      { path: "/api/pilot", method: "POST" },
      { path: "/api/waitlist", method: "POST" },
    ],
  });
}
