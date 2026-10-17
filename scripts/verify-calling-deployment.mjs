import { pathToFileURL } from 'node:url';
import { setTimeout } from 'node:timers/promises';

export async function verifyCallingDeployment({ origin, commit, bypass, fetcher = fetch, attempts = 12, pause = () => setTimeout(5000) }) {
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.origin !== origin || url.username || url.password || !/^[a-f0-9]{40}$/.test(commit)) {
    throw new Error('Set an HTTPS calling-server origin and the full release commit.');
  }
  if (bypass && !url.hostname.endsWith('.vercel.app')) throw new Error('Protection bypass is restricted to Vercel deployment hosts.');
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetcher(new URL('/api/calls/health', url), {
        headers: bypass ? { 'x-vercel-protection-bypass': bypass } : {},
        cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(12000),
      });
      if (response.ok) {
        const health = await response.json();
        if (health.ok === true && health.commit === commit && health.callingConfigured === true && health.storageReachable === true && health.pushConfigured === true) return;
      }
    } catch { /* Retry propagation and transient failures without printing remote bodies or secrets. */ }
    if (attempt + 1 < attempts) await pause();
  }
  throw new Error('Calling-server verification failed: the expected commit, storage, and push configuration are not ready.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await verifyCallingDeployment({ origin: process.env.CALLING_DEPLOYMENT_URL, commit: process.env.CALLING_DEPLOYMENT_COMMIT, bypass: process.env.VERCEL_AUTOMATION_BYPASS_SECRET });
    console.log(`Verified calling server ${process.env.CALLING_DEPLOYMENT_URL} at ${process.env.CALLING_DEPLOYMENT_COMMIT}. No calls placed.`);
  } catch (error) {
    console.error(error.message); process.exitCode = 1;
  }
}
