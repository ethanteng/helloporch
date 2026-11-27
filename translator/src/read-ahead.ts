/** Starts reading `source` now, so it doesn't wait for whoever reads it later. The one later reader gets everything
 * already read, then the rest as it arrives, and the source's error, if any, after that. `finished` resolves once the
 * source has ended either way, and never rejects. */
export function readAhead<T>(source: AsyncIterable<T>): AsyncIterable<T> & { finished: Promise<void> } {
  const items: T[] = [];
  let ended = false, failed = false, failure: unknown;
  let wake: (() => void) | undefined;
  const finished = (async () => {
    try { for await (const item of source) { items.push(item); wake?.(); } }
    catch (error) { failed = true; failure = error; }
    finally { ended = true; wake?.(); }
  })();
  return {
    finished,
    async *[Symbol.asyncIterator]() {
      for (let i = 0; ;) {
        if (i < items.length) { yield items[i++]; continue; }
        if (ended) { if (failed) throw failure; return; }
        await new Promise<void>(resolve => { wake = resolve; });
        wake = undefined;
      }
    },
  };
}
