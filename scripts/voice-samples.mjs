// Renders the bedside's real spoken sentences with a few ElevenLabs voices per language, next to
// the built-in voice Porch uses today, into .voice-samples/index.html for side-by-side listening.
//
//   node --env-file=.env.local scripts/voice-samples.mjs list      # candidate voices, no credits used
//   node --env-file=.env.local scripts/voice-samples.mjs render    # renders samples (asks ElevenLabs once per clip)
//
// Options: --name Ethan, --voices 3 (per language), --model eleven_v4, --max-chars 8000, --repick.
// Clips already rendered are kept, so a rerun only pays for new ones.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
const mode = ["list", "render"].includes(args[0]) ? args[0] : "render";
const option = (name, fallback) => { const i = args.indexOf(`--${name}`); return i >= 0 && args[i + 1] ? args[i + 1] : fallback; };
const name = option("name", "Ethan");
const perLanguage = Number(option("voices", "3"));
const model = option("model", "eleven_v4");
const maxChars = Number(option("max-chars", "8000"));
const key = process.env.ELEVENLABS_API_KEY;
if (!key) { console.error("Set ELEVENLABS_API_KEY in .env.local, then run with node --env-file=.env.local."); process.exit(1); }

const out = join(import.meta.dirname, "..", ".voice-samples");
const manifestPath = join(out, "voices.json");

// The bedside's own wording (ios/PorchCore/Sources/PorchCore/BedsideLanguage.swift), with "Sent"
// times as the bedside's relative DateFormatter prints them for each locale.
const languages = [
  { id: "en", label: "English", code: "en", library: ["en"], say: "Samantha",
    native: v => v.language === "en" && /american/i.test(v.accent),
    sentences: [`${name} is dropping in with video. Connecting in five seconds.`, `Message from ${name}. Sent Today at 3:15 PM.`,
      `${name} didn't answer. Please leave a message after the beep.`,
      "Sorry, no one can come to the phone right now. Please leave a message after the tone, then hang up."] },
  { id: "zh-Hant", label: "繁體中文 · Taiwan Mandarin", code: "zh", library: ["zh"], say: "Meijia",
    native: v => v.language === "zh" && (/taiwan/i.test(v.accent) || v.locale === "cmn-TW"),
    sentences: [`${name}要和您視訊通話，五秒後接通。`, `${name}的留言，傳送於今天 下午3:15。`, `${name}沒有接聽。請在嗶聲後留言。`] },
  { id: "zh-Hans", label: "简体中文 · Mainland Mandarin", code: "zh", library: ["zh"], say: "Tingting",
    native: v => v.language === "zh" && /standard|beijing/i.test(v.accent) && v.locale === "cmn-CN",
    sentences: [`${name}要和您视频通话，五秒后接通。`, `${name}的留言，发送于今天 15:15。`, `${name}没有接听。请在嘀声后留言。`] },
  { id: "yue", label: "廣東話 · Cantonese", code: "yue", library: ["yue", "zh"], say: "Sinji",
    native: v => v.language === "yue" || (v.language === "zh" && /cantonese/i.test(v.accent)),
    sentences: [`${name}想同您視像通話，五秒後接通。`, `${name}嘅留言，喺今日 下午3:15傳送。`, `${name}冇接聽。請喺嘟一聲之後留言。`] },
  { id: "es", label: "Español · Spain", code: "es", library: ["es"], say: "Mónica",
    native: v => v.language === "es" && v.locale === "es-ES",
    sentences: [`${name} quiere hablar con usted por vídeo. La llamada se conectará en cinco segundos.`, `Mensaje de ${name}. Enviado hoy, 15:15.`,
      `${name} no ha contestado. Deje un mensaje después del pitido.`] },
];
const script = language => language.sentences.join("\n\n");

async function request(path, init = {}) {
  const response = await fetch(`https://api.elevenlabs.io${path}`, { ...init, headers: { "xi-api-key": key, ...init.headers }, signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error(`${init.method ?? "GET"} ${path.split("?")[0]} failed (${response.status}): ${(await response.text()).slice(0, 300)}`);
  return response;
}

// Only voices native to the language and accent: many English voices are also "verified" in Chinese or Spanish.
// Calm, everyday delivery suits a bedside better than social-media or character voices.
const everyday = ["conversational", "narrative_story", "informative_educational"];
const rank = (a, b) => (everyday.includes(b.use_case) - everyday.includes(a.use_case)) || b.usage_character_count_1y - a.usage_character_count_1y;
// Library voices with their own per-use rate cost more than the plan's characters.
const extraCost = voice => Number(voice.fiat_rate) > 0;

async function candidates(language) {
  const found = new Map();
  for (const code of language.library) {
    for (let page = 0; page < 3; page++) {
      const params = new URLSearchParams({ language: code, page_size: "100", page: String(page), sort: "usage_character_count_1y", include_custom_rates: "false" });
      const { voices, has_more } = await (await request(`/v1/shared-voices?${params}`)).json();
      for (const voice of voices) if (!found.has(voice.voice_id) && language.native(voice) && !extraCost(voice)) found.set(voice.voice_id, voice);
      if (!has_more) break;
    }
  }
  return [...found.values()].sort(rank);
}

// The most-used voices, with at least one woman's and one man's voice when the library has both.
function pick(voices, count) {
  const chosen = [];
  for (const gender of ["female", "male"]) {
    const voice = voices.find(v => v.gender === gender);
    if (voice && chosen.length < count) chosen.push(voice);
  }
  for (const voice of voices) if (chosen.length < count && !chosen.includes(voice)) chosen.push(voice);
  return chosen.sort(rank);
}

const summary = v => ({ voice_id: v.voice_id, public_owner_id: v.public_owner_id, name: v.name, gender: v.gender, age: v.age,
  accent: v.accent, use_case: v.use_case, notice_period: v.notice_period ?? null, added: !!v.is_added_by_user });

if (mode === "list") {
  for (const language of languages) {
    const voices = await candidates(language);
    console.log(`\n${language.label}: ${voices.length} matching voices`);
    for (const v of voices.slice(0, 12)) console.log(`  ${v.voice_id}  ${v.name} · ${v.gender} · ${v.age} · ${v.accent} · ${v.use_case} · ${v.usage_character_count_1y.toLocaleString()} chars/yr`);
  }
  process.exit(0);
}

mkdirSync(out, { recursive: true });
// Picks are saved so a rerun renders the same voices, even as the library's rankings move.
let manifest = existsSync(manifestPath) && !args.includes("--repick") ? JSON.parse(readFileSync(manifestPath, "utf8")) : {};
for (const language of languages) {
  if (manifest[language.id]?.length) continue;
  manifest[language.id] = pick(await candidates(language), perLanguage).map(summary);
  if (!manifest[language.id].length) console.warn(`No library voices matched ${language.label}; only the built-in voice will be shown.`);
}
writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));

const clip = (language, voice) => join(out, language.id, `${voice.voice_id}.mp3`);
const pending = languages.flatMap(language => manifest[language.id].filter(v => !existsSync(clip(language, v))).map(voice => ({ language, voice })));
const characters = pending.reduce((sum, { language }) => sum + script(language).length, 0);
console.log(`${pending.length} clips to render with ${model}, ${characters.toLocaleString()} characters.`);
if (characters > maxChars) { console.error(`That's over --max-chars ${maxChars}; rerun with a higher limit to go ahead.`); process.exit(1); }

for (const language of languages) {
  mkdirSync(join(out, language.id), { recursive: true });
  // The Mac's compact voice for each locale is the same family the iPad falls back to by default.
  const builtIn = join(out, language.id, "built-in.m4a");
  if (!existsSync(builtIn)) {
    const aiff = join(out, language.id, "built-in.aiff");
    try {
      execFileSync("say", ["-v", language.say, "-o", aiff, script(language)]);
      execFileSync("afconvert", ["-f", "m4af", "-d", "aac", aiff, builtIn]);
    } catch { console.warn(`Couldn't render the built-in ${language.say} voice.`); }
    rmSync(aiff, { force: true });
  }
}
for (const { language, voice } of pending) {
  if (!voice.added) {
    const response = await request(`/v1/voices/add/${voice.public_owner_id}/${voice.voice_id}`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ new_name: `Porch ${language.id} · ${voice.name}`.slice(0, 100) }) });
    const { voice_id } = await response.json();
    Object.assign(voice, { added: true, voice_id: voice_id ?? voice.voice_id });
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  }
  const response = await request(`/v1/text-to-speech/${voice.voice_id}?output_format=mp3_44100_128`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: script(language), model_id: model, language_code: language.code }) });
  writeFileSync(clip(language, voice), Buffer.from(await response.arrayBuffer()));
  console.log(`  ${language.id}: ${voice.name}`);
}

const escape = value => String(value ?? "").replace(/[<>&"]/g, c => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;" })[c]);
// Audio is embedded so the page is one file that plays anywhere, including when sent to family.
const embed = path => `data:${path.endsWith(".mp3") ? "audio/mpeg" : "audio/mp4"};base64,${readFileSync(join(out, path)).toString("base64")}`;
const player = (title, detail, src) => existsSync(join(out, src))
  ? `<li><div><strong>${escape(title)}</strong><span>${escape(detail)}</span></div><audio controls preload="metadata" src="${embed(src)}"></audio></li>` : "";
const sections = languages.map(language => `<section><h2>${escape(language.label)}</h2>
<blockquote>${language.sentences.map(escape).join("<br>")}</blockquote><ul>
${player("Built-in voice (today)", `Apple ${language.say}, compact`, `${language.id}/built-in.m4a`)}
${manifest[language.id].filter(v => existsSync(clip(language, v))).map(v => player(v.name, [v.gender, v.age, v.accent, v.use_case, v.voice_id].filter(Boolean).join(" · "), `${language.id}/${v.voice_id}.mp3`)).join("\n")}
</ul></section>`).join("\n");
writeFileSync(join(out, "index.html"), `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Porch voice samples</title><style>
:root { --bg: #faf8f5; --fg: #1f1d1a; --muted: #6b665f; --card: #fff; --line: #e6e1d9; color-scheme: light dark; }
@media (prefers-color-scheme: dark) { :root { --bg: #171614; --fg: #f1eee9; --muted: #a39d94; --card: #22201d; --line: #36332e; } }
body { margin: 0 auto; max-width: 760px; padding: 24px 16px 64px; background: var(--bg); color: var(--fg); font: 16px/1.5 -apple-system, system-ui, sans-serif; }
h1 { font-size: 24px; margin: 0 0 4px; } h2 { font-size: 19px; margin: 32px 0 8px; } p { color: var(--muted); margin: 0; }
blockquote { margin: 0 0 12px; padding: 10px 14px; border-left: 3px solid var(--line); color: var(--muted); }
ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
li { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; display: grid; gap: 8px; }
li span { display: block; color: var(--muted); font-size: 13px; word-break: break-all; } audio { width: 100%; }
</style></head><body><h1>Porch voice samples</h1><p>ElevenLabs ${escape(model)} reading the bedside's own sentences, next to the built-in voice it uses today.</p>
${sections}</body></html>`);
console.log(`Open ${join(out, "index.html")}`);
