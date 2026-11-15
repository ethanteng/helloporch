// Compares LiveKit Inference speech-to-text models on recorded clips of mixed English and Mandarin.
// node scripts/stt-bench.ts <env file with LIVEKIT_*> <folder of 16 kHz mono s16le .pcm clips and clips.json>
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { initializeLogger, inference, stt } from '@livekit/agents';
import { AudioFrame } from '@livekit/rtc-node';

const [envFile, folder] = process.argv.slice(2);
for (const line of readFileSync(envFile, 'utf8').split('\n')) {
  const m = line.match(/^(LIVEKIT_URL|LIVEKIT_API_KEY|LIVEKIT_API_SECRET)=(.*)$/);
  if (m) process.env[m[1]] = m[2].trim().replace(/^"|"$/g, '');
}
initializeLogger({ pretty: true, level: 'warn' });
const clips: { id: string; text: string }[] = JSON.parse(readFileSync(join(folder, 'clips.json'), 'utf8'));
const only = process.env.MODELS?.split(',');
const candidates: { name: string; make: () => stt.STT }[] = [
  { name: 'speechmatics cmn_en', make: () => new inference.STT({ model: 'speechmatics/enhanced', language: 'cmn_en' }) },
  { name: 'google gemini-3.5 en+zh-TW', make: () => new inference.STT({ model: 'google/gemini-3.5-transcribe-live', modelOptions: { language_codes: ['en-US', 'cmn-Hant-TW'] } }) },
  { name: 'deepgram nova-3 multi', make: () => new inference.STT({ model: 'deepgram/nova-3', language: 'multi' }) },
  { name: 'deepgram flux multi', make: () => new inference.STT({ model: 'deepgram/flux-general-multi', modelOptions: { language_hint: ['en', 'zh'] } }) },
  { name: 'assemblyai u3.6 pro', make: () => new inference.STT({ model: 'assemblyai/universal-3-6-pro' }) },
  { name: 'cartesia ink-2', make: () => new inference.STT({ model: 'cartesia/ink-2' }) },
  { name: 'xai stt-1', make: () => new inference.STT({ model: 'xai/stt-1' }) },
];

async function transcribe(engine: stt.STT, clip: string) {
  const pcm = readFileSync(join(folder, `${clip}.pcm`));
  const samples = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.length / 2);
  const stream = engine.stream();
  const finals: string[] = [];
  let audioEnd = 0, firstFinalAfterEnd = 0;
  const reading = (async () => {
    for await (const ev of stream) {
      if (ev.type === stt.SpeechEventType.FINAL_TRANSCRIPT && ev.alternatives?.[0].text.trim()) {
        finals.push(ev.alternatives[0].text.trim());
        if (audioEnd && !firstFinalAfterEnd) firstFinalAfterEnd = Date.now();
      }
    }
  })();
  const step = 320; // 20 ms frames, sent in real time
  const silence = new Int16Array(16000 * 2);
  // Lead with silence so a slow connection doesn't cost the first words.
  for (const part of [silence, samples, silence]) {
    for (let i = 0; i < part.length; i += step) {
      stream.pushFrame(new AudioFrame(part.slice(i, i + step), 16000, 1, Math.min(step, part.length - i)));
      await new Promise(r => setTimeout(r, 20));
    }
    if (part === samples) audioEnd = Date.now();
  }
  // endInput() trips over the inference stream's own VAD in agents 1.9.5, so wait for finals and close.
  const waitUntil = Date.now() + 6000;
  while (Date.now() < waitUntil && !firstFinalAfterEnd) await new Promise(r => setTimeout(r, 100));
  await new Promise(r => setTimeout(r, 1500));
  try { stream.close(); } catch { /* already closed */ }
  void reading.catch(() => {});
  return { text: finals.join(' '), lag: firstFinalAfterEnd ? firstFinalAfterEnd - audioEnd : undefined };
}

for (const c of candidates.filter(c => !only || only.some(o => c.name.includes(o)))) {
  console.log(`\n== ${c.name}`);
  try {
    const engine = c.make();
    // The LiveKit project allows 5 speech-to-text connections at once (calls need some too), so run 3 at a time.
    const results: { text: string; lag?: number }[] = [];
    for (let i = 0; i < clips.length; i += 3) {
      results.push(...await Promise.all(clips.slice(i, i + 3).map(clip => transcribe(engine, clip.id)
        .catch(e => ({ text: `ERROR ${String(e).slice(0, 120)}`, lag: undefined })))));
    }
    clips.forEach((clip, i) => console.log(`${clip.id} ${results[i].lag === undefined ? '   -  ' : `${(results[i].lag! / 1000).toFixed(1)}s`.padStart(5)} | ${results[i].text}\n${' '.repeat(9)}| ${clip.text}`));
  } catch (e) { console.log('failed:', String(e).slice(0, 300)); }
}
process.exit(0);
