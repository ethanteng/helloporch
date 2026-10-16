"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Room, RoomEvent, Track, ConnectionState } from "livekit-client";
import styles from "./call.module.css";

type Phase = "idle" | "joining" | "waiting" | "connected" | "reconnecting";

export default function CallPrototype() {
  const [name, setName] = useState("");
  const [roomName, setRoomName] = useState("");
  const [code, setCode] = useState("");
  const [mode, setMode] = useState<"voice" | "video">("video");
  const [phase, setPhase] = useState<Phase>("idle");
  const [status, setStatus] = useState("Ready when you are.");
  const [muted, setMuted] = useState(false);
  const [cameraOff, setCameraOff] = useState(false);
  const [changingMedia, setChangingMedia] = useState(false);
  const [hasVideo, setHasVideo] = useState(false);
  const roomRef = useRef<Room | null>(null);
  const attempt = useRef(0);
  const requestRef = useRef<AbortController | null>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const attached = useRef<Track[]>([]);
  const remoteVideo = useRef<HTMLDivElement>(null);
  const localVideo = useRef<HTMLDivElement>(null);
  const audio = useRef<HTMLDivElement>(null);
  const inCall = phase !== "idle";

  const clearMedia = useCallback(() => {
    attached.current.forEach((track) => track.detach().forEach((element) => element.remove()));
    attached.current = [];
    remoteVideo.current?.replaceChildren();
    localVideo.current?.replaceChildren();
    audio.current?.replaceChildren();
  }, []);

  const finish = useCallback((message: string) => {
    attempt.current += 1;
    requestRef.current?.abort();
    if (timerRef.current) clearTimeout(timerRef.current);
    const room = roomRef.current;
    roomRef.current = null;
    void room?.disconnect();
    clearMedia();
    setHasVideo(false);
    setPhase("idle");
    setChangingMedia(false);
    setStatus(message);
  }, [clearMedia]);

  useEffect(() => {
    const leave = () => {
      attempt.current += 1;
      requestRef.current?.abort();
      if (timerRef.current) clearTimeout(timerRef.current);
      const room = roomRef.current;
      roomRef.current = null;
      void room?.disconnect();
      clearMedia();
    };
    window.addEventListener("pagehide", leave);
    return () => {
      window.removeEventListener("pagehide", leave);
      leave();
    };
  }, [clearMedia]);

  async function join(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (phase !== "idle") return;
    if (!window.isSecureContext || !navigator.mediaDevices) {
      setStatus("Open this page over HTTPS, or use localhost on this computer, to allow microphone and camera access.");
      return;
    }
    const current = ++attempt.current;
    const abort = new AbortController();
    requestRef.current = abort;
    setPhase("joining");
    setStatus("Connecting…");
    setMuted(false);
    setCameraOff(false);
    let room: Room | undefined;
    let hasPeer = false;

    try {
      const response = await fetch("/api/calls/token", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${code.trim()}` },
        body: JSON.stringify({ name: name.trim(), room: roomName.trim().toLowerCase(), mode }),
        cache: "no-store",
        signal: abort.signal,
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error ?? "Couldn't create the call.");
      if (current !== attempt.current) return;
      room = new Room({ adaptiveStream: true, dynacast: true });
      const activeRoom = room;
      roomRef.current = activeRoom;
      const active = () => current === attempt.current && roomRef.current === activeRoom;

      const syncMedia = () => {
        if (!active()) return;
        clearMedia();
        let remoteShown = false;
        for (const participant of activeRoom.remoteParticipants.values()) {
          for (const publication of participant.trackPublications.values()) {
            const track = publication.track;
            if (!track || publication.isMuted) continue;
            if (track.kind === Track.Kind.Audio) {
              audio.current?.appendChild(track.attach());
              attached.current.push(track);
            } else if (mode === "video" && !remoteShown) {
              remoteVideo.current?.appendChild(track.attach());
              attached.current.push(track);
              remoteShown = true;
            }
          }
        }
        setHasVideo(remoteShown);
        if (mode === "video") {
          const track = activeRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.track;
          if (track && !track.isMuted) {
            const element = track.attach();
            element.muted = true;
            localVideo.current?.appendChild(element);
            attached.current.push(track);
          }
        }
      };
      const syncParticipants = () => {
        if (!active()) return;
        if (activeRoom.remoteParticipants.size > 0) {
          hasPeer = true;
          if (timerRef.current) clearTimeout(timerRef.current);
          setPhase("connected");
          setStatus(`${mode === "voice" ? "Voice" : "Video"} call connected.`);
        } else if (hasPeer) {
          finish("Call ended. You're ready for another call.");
          return;
        } else {
          setPhase("waiting");
          setStatus(`Waiting for the other person in ${roomName.trim().toLowerCase()} (${mode}).`);
        }
        syncMedia();
      };
      activeRoom.on(RoomEvent.TrackSubscribed, syncMedia)
        .on(RoomEvent.TrackUnsubscribed, syncMedia)
        .on(RoomEvent.TrackMuted, syncMedia)
        .on(RoomEvent.TrackUnmuted, syncMedia)
        .on(RoomEvent.LocalTrackPublished, syncMedia)
        .on(RoomEvent.LocalTrackUnpublished, syncMedia)
        .on(RoomEvent.ParticipantConnected, syncParticipants)
        .on(RoomEvent.ParticipantDisconnected, syncParticipants)
        .on(RoomEvent.Reconnecting, () => {
          if (active()) { setPhase("reconnecting"); setStatus("Connection interrupted. Reconnecting…"); }
        })
        .on(RoomEvent.Reconnected, syncParticipants)
        .on(RoomEvent.Disconnected, () => {
          if (active()) finish("The call disconnected. You can join again.");
        })
        .on(RoomEvent.AudioPlaybackStatusChanged, () => {
          if (active() && !activeRoom.canPlaybackAudio) setStatus("Your browser blocked sound. Press Enable sound below.");
        });

      await activeRoom.connect(data.serverUrl, data.token);
      if (!active()) { await activeRoom.disconnect(); return; }
      await activeRoom.localParticipant.setMicrophoneEnabled(true);
      if (!active()) { await activeRoom.disconnect(); return; }
      if (mode === "video") await activeRoom.localParticipant.setCameraEnabled(true);
      if (!active()) { await activeRoom.disconnect(); return; }
      await activeRoom.startAudio();
      syncParticipants();
      if (!hasPeer) timerRef.current = setTimeout(() => {
        if (active()) finish("No one joined within 90 seconds. You can try again.");
      }, 90_000);
    } catch (error) {
      if (roomRef.current === room) roomRef.current = null;
      if (room) await room.disconnect();
      if (current !== attempt.current) return;
      const mediaError = error instanceof Error && ["NotAllowedError", "PermissionDeniedError"].includes(error.name);
      finish(mediaError
        ? "Allow microphone access (and camera access for video), then join again."
        : error instanceof Error ? error.message : "Couldn't start the call. Try again.");
    }
  }

  async function toggleMedia(camera: boolean) {
    const room = roomRef.current;
    if (!room || room.state !== ConnectionState.Connected || changingMedia) return;
    setChangingMedia(true);
    try {
      if (camera) {
        const enabled = !room.localParticipant.isCameraEnabled;
        await room.localParticipant.setCameraEnabled(enabled);
        if (roomRef.current !== room) { await room.disconnect(); return; }
        if (roomRef.current === room) setCameraOff(!enabled);
      } else {
        const enabled = !room.localParticipant.isMicrophoneEnabled;
        await room.localParticipant.setMicrophoneEnabled(enabled);
        if (roomRef.current !== room) { await room.disconnect(); return; }
        if (roomRef.current === room) setMuted(!enabled);
      }
    } catch {
      if (roomRef.current === room) setStatus(`Couldn't change the ${camera ? "camera" : "microphone"}. Try again.`);
    } finally {
      if (roomRef.current === room) setChangingMedia(false);
    }
  }

  return (
    <main className={styles.page}>
      <a className={styles.brand} href="/">Porch<span>.</span></a>
      <p className={styles.eyebrow}>Calling prototype</p>
      <h1>A familiar voice.<br />A familiar face.</h1>
      <p className={styles.intro}>Join someone on Porch. Use the same room name and call mode on both devices.</p>
      <div className={styles.layout}>
        <section className={styles.card} aria-label="Call settings">
          <form onSubmit={join}>
            <fieldset disabled={inCall}>
              <label htmlFor="name">Your name</label>
              <input id="name" value={name} onChange={(e) => setName(e.target.value)} placeholder="David" required maxLength={80} autoComplete="given-name" />
              <label htmlFor="room">Room name</label>
              <input id="room" value={roomName} onChange={(e) => setRoomName(e.target.value.toLowerCase())} placeholder="family-david" required pattern="[a-z0-9][a-z0-9-]{0,63}" maxLength={64} autoCapitalize="none" autoCorrect="off" spellCheck={false} />
              <label htmlFor="code">Prototype access code</label>
              <input id="code" type="password" value={code} onChange={(e) => setCode(e.target.value)} required minLength={16} maxLength={256} autoComplete="off" />
              <label htmlFor="mode">Call mode</label>
              <select id="mode" value={mode} onChange={(e) => setMode(e.target.value as "voice" | "video")}>
                <option value="video">Video call</option>
                <option value="voice">Voice only · camera stays off</option>
              </select>
              <button className={styles.primary} type="submit">Join call</button>
            </fieldset>
          </form>
          <p className={styles.note}>Both people join manually. This prototype doesn’t send incoming-call notifications. Share the access code only with your testers.</p>
        </section>
        <section className={styles.call} aria-label="Call">
          <div className={styles.stage}>
            <div className={styles.remoteVideo} ref={remoteVideo} />
            {!hasVideo && <div className={styles.placeholder}>
              <span aria-hidden="true">{mode === "voice" ? "◉" : "✳"}</span>
              <p>{!inCall ? "Your call starts here" : mode === "voice" ? "Voice call · camera is off" : "Waiting for video"}</p>
            </div>}
            <div className={styles.localVideo} ref={localVideo} />
          </div>
          <p className={styles.status} role="status" aria-live="polite">{status}</p>
          {inCall && <div className={styles.controls}>
            <button onClick={() => void toggleMedia(false)} disabled={phase === "joining" || phase === "reconnecting" || changingMedia}>{muted ? "Unmute" : "Mute"}</button>
            {mode === "video" && <button onClick={() => void toggleMedia(true)} disabled={phase === "joining" || phase === "reconnecting" || changingMedia}>{cameraOff ? "Camera on" : "Camera off"}</button>}
            <button onClick={() => void roomRef.current?.startAudio().catch(() => setStatus("Couldn't enable sound. Check your browser's audio permissions."))}>Enable sound</button>
            <button className={styles.end} onClick={() => finish("Call ended. You're ready for another call.")}>End call</button>
          </div>}
          <div ref={audio} />
        </section>
      </div>
    </main>
  );
}
