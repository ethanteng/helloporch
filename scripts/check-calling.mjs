import { existsSync } from "node:fs";
import { RoomServiceClient, SipClient, TokenVerifier } from "livekit-server-sdk";

// Read local secrets without putting them in command arguments or tool output.
if (existsSync(".env.local")) process.loadEnvFile(".env.local");
const args = process.argv.slice(2);
if (args.some((argument) => argument !== "--phone" && !argument.startsWith("--endpoint="))) {
  console.error("Usage: npm run calls:check -- [--phone] [--endpoint=https://your-porch-server]");
  process.exit(1);
}
const phone = args.includes("--phone");
const endpoint = args.find((argument) => argument.startsWith("--endpoint="))?.slice("--endpoint=".length);
const required = ["LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET", "PORCH_CALL_ACCESS_CODE"];
if (phone) required.push("LIVEKIT_SIP_OUTBOUND_TRUNK_ID", "PORCH_PHONE_NUMBERS");
const missing = required.filter((key) => !process.env[key]?.trim());
if (missing.length) {
  console.error(`Setup needed in .env.local: ${missing.join(", ")}`);
  console.error("Enter credentials in the local file, never in chat. No calls were placed.");
  process.exit(1);
}

try {
  const server = new URL(process.env.LIVEKIT_URL);
  if (server.protocol !== "wss:" || server.username || server.password || server.search || server.hash ||
      server.hostname === "your-project.livekit.cloud") throw new Error("url");
} catch {
  console.error("Replace LIVEKIT_URL with the wss:// URL from your LiveKit project's settings.");
  process.exit(1);
}
if (!/^[\x21-\x7e]{16,256}$/.test(process.env.PORCH_CALL_ACCESS_CODE)) {
  console.error("PORCH_CALL_ACCESS_CODE must contain 16–256 characters without spaces.");
  process.exit(1);
}
if (phone) {
  const numbers = process.env.PORCH_PHONE_NUMBERS.split(",").map((number) => number.trim()).filter(Boolean);
  if (!numbers.length || !numbers.every((number) => /^\+[1-9][0-9]{6,14}$/.test(number))) {
    console.error("PORCH_PHONE_NUMBERS needs approved destinations with + and country code, separated by commas.");
    process.exit(1);
  }
}

let endpointURL;
if (endpoint) {
  try {
    endpointURL = new URL(endpoint);
    if (endpointURL.username || endpointURL.password || endpointURL.search || endpointURL.hash ||
        (endpointURL.pathname !== "/" && endpointURL.pathname !== "") ||
        !(endpointURL.protocol === "https:" || (endpointURL.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(endpointURL.hostname)))) throw new Error("url");
  } catch {
    console.error("Use --endpoint=https://your-porch-server with no path or credentials. HTTP localhost is allowed.");
    process.exit(1);
  }
}

const host = process.env.LIVEKIT_URL.replace(/^wss:/, "https:");
const options = { requestTimeout: 10, failover: false };
let stage = "LiveKit authentication";
try {
  const rooms = new RoomServiceClient(host, process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, options);
  // Filtered lookup authenticates without creating a room or joining media.
  await rooms.listRooms(["porch-configuration-check"]);
  console.log("LiveKit project URL and API credentials verified.");

  if (phone) {
    stage = "outbound SIP trunk lookup";
    const sip = new SipClient(host, process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, options);
    const trunks = await sip.listSipOutboundTrunk({ trunkIds: [process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID] });
    const trunk = trunks.find((item) => item.sipTrunkId === process.env.LIVEKIT_SIP_OUTBOUND_TRUNK_ID);
    if (!trunk?.address || !trunk.numbers.some((number) => /^\+[1-9][0-9]{6,14}$/.test(number))) {
      console.error("The configured outbound trunk needs a provider address and an explicit outgoing caller-ID number.");
      process.exit(1);
    }
    console.log("LiveKit outbound SIP trunk found, with an outgoing caller-ID number.");
    console.log("Approved destination list is valid. Provider authentication still needs a real fallback call test.");
  }

  if (endpointURL) {
    stage = "Porch token endpoint";
    const response = await fetch(new URL("/api/calls/token", endpointURL), {
      method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${process.env.PORCH_CALL_ACCESS_CODE}` },
      body: JSON.stringify({ room: "configuration-check", mode: "voice", name: "Configuration check" }),
      signal: AbortSignal.timeout(15000), redirect: "error",
    });
    if (!response.ok) {
      console.error(`Porch token endpoint returned HTTP ${response.status}. Check its deployment and environment variables.`);
      process.exit(1);
    }
    const data = await response.json();
    const claims = await new TokenVerifier(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET).verify(data.token);
    if (data.serverUrl !== process.env.LIVEKIT_URL || claims.video?.room !== "porch-voice-configuration-check" ||
        claims.video?.canPublishSources?.join(",") !== "microphone") throw new Error("token");
    console.log("Porch token endpoint verified with room-scoped, microphone-only credentials.");
  }
  console.log("Checks complete. No phone calls placed and no media sessions created.");
} catch (error) {
  // SDK messages can include provider details. Show status codes, never secrets.
  const code = error && typeof error === "object" && "status" in error ? ` (HTTP ${error.status})` : "";
  console.error(`Couldn't verify ${stage}${code}. Check the credentials, project, and network connection.`);
  process.exitCode = 1;
}
