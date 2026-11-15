// The bedside's languages (`BedsideLanguage` in lib/family/household.ts) and what live translation needs for each:
// how Claude names it, Google's speech recognition code, and ElevenLabs' language code.
export const languages = {
  en: { name: "English", recognize: "en-US", speak: "en" },
  "zh-Hant": { name: "Mandarin Chinese, written in Traditional characters as in Taiwan", recognize: "cmn-Hant-TW", speak: "zh" },
  "zh-Hans": { name: "Mandarin Chinese, written in Simplified characters as in mainland China", recognize: "cmn-Hans-CN", speak: "zh" },
  "yue-Hant": { name: "Cantonese, written in Traditional characters as in Hong Kong", recognize: "yue-Hant-HK", speak: "yue" },
  es: { name: "Spanish, as spoken in Spain", recognize: "es-ES", speak: "es" },
  tl: { name: "Tagalog (Filipino), as spoken in the Philippines", recognize: "fil-PH", speak: "fil" },
  ko: { name: "Korean, as spoken in South Korea", recognize: "ko-KR", speak: "ko" },
} as const;
export type Language = keyof typeof languages;

export function isLanguage(value: unknown): value is Language {
  return typeof value === "string" && Object.hasOwn(languages, value);
}
