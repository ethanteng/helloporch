import { randomUUID } from "node:crypto";
import { AccessToken, RoomConfiguration, TrackSource } from "livekit-server-sdk";
import { authorizeCalls, callInput, callJSON as json } from "../../../../lib/calls/server.ts";

export const runtime = "nodejs";

// Shared-code authentication is limited to trusted prototype testers.
export async function POST(request: Request) {
  const config = authorizeCalls(request);
  if (config instanceof Response) return config;
  const { apiKey, apiSecret, serverUrl } = config;
  const input = await callInput(request);
  if (input instanceof Response) return input;
  const { room, mode, name } = input as Record<string, unknown>;
  if (typeof room !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(room) ||
      (mode !== "voice" && mode !== "video") ||
      typeof name !== "string" || !name.trim() || name.trim().length > 80) {
    return json({ error: "Enter a room name, your name, and voice or video mode." }, 400);
  }

  try {
    // Mode is part of the room namespace so video cannot leak into voice calls.
    const roomName = `porch-${mode}-${room}`;
    const token = new AccessToken(apiKey, apiSecret, {
      identity: randomUUID(),
      name: name.trim(),
      ttl: "10m",
    });
    token.roomConfig = new RoomConfiguration({ maxParticipants: 2, emptyTimeout: 90, departureTimeout: 10 });
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: false,
      canPublishSources: mode === "voice"
        ? [TrackSource.MICROPHONE]
        : [TrackSource.MICROPHONE, TrackSource.CAMERA],
    });
    return json({ token: await token.toJwt(), serverUrl, room: roomName });
  } catch {
    return json({ error: "Couldn't create a call. Check the server's LiveKit configuration." }, 500);
  }
}
