"use client";
import { useState } from "react";
import { day } from "./format";

/** A setup link, shown once with buttons to copy it on its own or in a message. */
export default function NewLink({ label, link, message, expiresAt }: { label: string; link: string; message: string; expiresAt: number }) {
  const [copied, setCopied] = useState<"link" | "message" | "failed">();
  const copy = async (what: "link" | "message") => {
    try { await navigator.clipboard.writeText(what === "link" ? link : message); setCopied(what); }
    catch { setCopied("failed"); }
  };
  return (
    <div className="new-link" role="status">
      <p><strong>Setup link for {label}</strong>, until {day(expiresAt)}. Copy it now: it isn&apos;t shown again. If it&apos;s lost, cancel it and make a new one.</p>
      <input readOnly value={link} aria-label="Setup link" onFocus={event => event.currentTarget.select()} />
      <div className="row">
        <button type="button" onClick={() => copy("link")}>{copied === "link" ? "Copied" : "Copy link"}</button>
        <button type="button" className="secondary" onClick={() => copy("message")}>{copied === "message" ? "Copied" : "Copy message"}</button>
        {copied === "failed" && <span className="error">Couldn&apos;t copy. Select the link and copy it.</span>}
      </div>
    </div>
  );
}
