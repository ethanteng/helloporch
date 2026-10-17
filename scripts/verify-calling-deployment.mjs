import { pathToFileURL } from 'node:url';
import { setTimeout } from 'node:timers/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

export function vercelHealthFetcher(run = promisify(execFile)) {
  return async url => {
    if (url.protocol !== 'https:' || !url.hostname.endsWith('.vercel.app') || url.username || url.password || url.pathname !== '/api/calls/health' || url.search || url.hash) {
      throw new Error('Authenticated checks are restricted to the Vercel health endpoint.');
    }
    // The CLI uses VERCEL_TOKEN from its environment; no token in arguments,
    // response files, or logs. Native curl does not follow redirects by default.
    const { stdout } = await run('vercel', ['curl', url.href, '--silent', '--show-error', '--fail', '--max-time', '15'], { timeout: 20000, maxBuffer: 65536 });
    return new Response(stdout);
  };
}

export async function verifyCallingDeployment({ origin, commit, fetcher = fetch, attempts = 12, pause = () => setTimeout(5000) }) {
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.origin !== origin || url.username || url.password || !/^[a-f0-9]{40}$/.test(commit)) {
    throw new Error('Set an HTTPS calling-server origin and the full release commit.');
  }
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetcher(new URL('/api/calls/health', url), {
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
    await verifyCallingDeployment({ origin: process.env.CALLING_DEPLOYMENT_URL, commit: process.env.CALLING_DEPLOYMENT_COMMIT,
      fetcher: process.env.CALLING_VERIFY_WITH_VERCEL_CLI === '1' ? vercelHealthFetcher() : fetch });
    console.log(`Verified calling server ${process.env.CALLING_DEPLOYMENT_URL} at ${process.env.CALLING_DEPLOYMENT_COMMIT}. No calls placed.`);
  } catch (error) {
    console.error(error.message); process.exitCode = 1;
  }
}
