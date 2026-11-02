"use client";

import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import styles from "./features.module.css";

type Tab = { id: string; label: string; content: ReactNode };

// Tabs follow the WAI-ARIA pattern: arrow keys, Home and End move between them.
// The open tab is kept in the URL hash, so /features#safety links straight to it, and a clip's own id, such as
// /features#phone-fallback, opens the tab it's in. Either way the page scrolls down to it, below the story.
export default function FeatureTabs({ tabs }: { tabs: Tab[] }) {
  const [active, setActive] = useState(tabs[0].id);
  // What to scroll to once its tab is showing: an element's id, or null for the tabs themselves.
  const [scrollTarget, setScrollTarget] = useState<{ id: string | null } | null>(null);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const fromHash = () => {
      const id = window.location.hash.slice(1);
      if (!id) return;
      if (tabs.some((tab) => tab.id === id)) {
        setActive(id);
        setScrollTarget({ id: null });
        return;
      }
      const panel = document.getElementById(id)?.closest<HTMLElement>("[role=tabpanel]");
      const tab = tabs.find((t) => panel?.id === `panel-${t.id}`);
      if (tab) {
        setActive(tab.id);
        setScrollTarget({ id });
      }
    };
    fromHash();
    window.addEventListener("hashchange", fromHash);
    return () => window.removeEventListener("hashchange", fromHash);
  }, [tabs]);

  // A hidden panel can't be scrolled to, so this waits for the render that shows it.
  useEffect(() => {
    if (!scrollTarget) return;
    const target = scrollTarget.id ? document.getElementById(scrollTarget.id) : root.current;
    target?.scrollIntoView({ block: "start" });
  }, [scrollTarget]);

  // Stop a clip that's still playing in a tab that's been closed.
  useEffect(() => {
    root.current?.querySelectorAll<HTMLVideoElement>("[role=tabpanel][hidden] video").forEach((video) => video.pause());
  }, [active]);

  function open(id: string, focus = false) {
    setActive(id);
    window.history.replaceState(null, "", `#${id}`);
    if (focus) document.getElementById(`tab-${id}`)?.focus();
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const index = tabs.findIndex((tab) => tab.id === active);
    const moves: Record<string, number> = {
      ArrowRight: (index + 1) % tabs.length,
      ArrowLeft: (index - 1 + tabs.length) % tabs.length,
      Home: 0,
      End: tabs.length - 1,
    };
    const next = moves[event.key];
    if (next === undefined) return;
    event.preventDefault();
    open(tabs[next].id, true);
  }

  return (
    <div ref={root} className={styles.tabs}>
      <div role="tablist" aria-label="Porch features" className={styles.tablist} onKeyDown={onKeyDown}>
        {tabs.map((tab) => (
          <button
            key={tab.id}
            id={`tab-${tab.id}`}
            type="button"
            role="tab"
            aria-selected={tab.id === active}
            aria-controls={`panel-${tab.id}`}
            tabIndex={tab.id === active ? 0 : -1}
            className={styles.tab}
            onClick={() => open(tab.id)}
          >
            {tab.label}
          </button>
        ))}
      </div>
      {tabs.map((tab) => (
        <div
          key={tab.id}
          id={`panel-${tab.id}`}
          role="tabpanel"
          aria-labelledby={`tab-${tab.id}`}
          hidden={tab.id !== active}
          className={styles.panel}
        >
          {tab.content}
        </div>
      ))}
    </div>
  );
}
