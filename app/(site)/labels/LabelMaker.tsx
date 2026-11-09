"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import { paintPreview, readPhoto, type Contact } from "@/lib/labels/artwork";
import { DEFAULT_HEIGHT, DEFAULT_WIDTH, MAX_CONTACTS, MAX_SETS, MAX_DIMENSION, MIN_DIMENSION, formatSize, makeSheets, parseDimensions, type Card, type Dimensions } from "@/lib/labels/layout";
import PhotoEditor from "./PhotoEditor";
import styles from "./labels.module.css";

const blankContact: Contact = { name: "", photo: null };
const defaultDimensions = { width: Number(DEFAULT_WIDTH), height: Number(DEFAULT_HEIGHT) };
const acceptImages = "image/jpeg,image/png,image/webp,image/avif,image/heic,image/heif,.jpg,.jpeg,.png,.webp,.avif,.heic,.heif";

type IconName = "photo" | "download" | "lock" | "chevron";
function Icon({ name }: { name: IconName }) {
  const paths: Record<IconName, ReactNode> = {
    photo: <><rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="9" r="1.5"/><path d="m3 16 4.5-4 3.2 2.8 4.4-4.4L21 16"/></>,
    download: <><path d="M12 3v12m-4-4 4 4 4-4"/><path d="M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/></>,
    lock: <><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3"/></>,
    chevron: <path d="m9 6 6 6-6 6"/>,
  };
  return <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

function Step({ number, title, children }: { number: number; title: string; children: ReactNode }) {
  return (
    <section className={styles.step} aria-labelledby={`labels-step-${number}`}>
      <div className={styles.stepTitle}>
        <span className={styles.stepNumber} aria-hidden="true">{number}</span>
        <h2 id={`labels-step-${number}`}>{title}</h2>
      </div>
      {children}
    </section>
  );
}

function Preview({ contacts, pages, dimensions, page }: { contacts: Contact[]; pages: Card[][]; dimensions: Dimensions; page: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true;
    if (canvas.current) {
      void paintPreview(canvas.current, contacts, pages[page], dimensions, page, pages.length, () => active)
        .catch(() => { if (active) setFailed(true); });
    }
    return () => { active = false; };
  }, [contacts, pages, dimensions, page]);
  return failed
    ? <p className={styles.previewError}>The preview isn’t available in this browser.</p>
    : <canvas ref={canvas} width={918} height={1188} className={styles.paper} role="img" aria-label={`Print sheet preview, page ${page + 1} of ${pages.length}`} />;
}

function saveDownload(url: string) {
  const link = document.createElement("a");
  link.href = url;
  link.download = "porch-phone-labels.pdf";
  document.body.append(link);
  link.click();
  link.remove();
}

export default function LabelMaker() {
  const [count, setContactCount] = useState(3);
  const [people, setPeople] = useState<Contact[]>(() => Array.from({ length: MAX_CONTACTS }, () => blankContact));
  const [width, setWidth] = useState(DEFAULT_WIDTH);
  const [height, setHeight] = useState(DEFAULT_HEIGHT);
  const [setCount, setSetCount] = useState(1);
  const [previewPage, setPreviewPage] = useState(0);
  const [uploads, setUploads] = useState<Record<number, { loading?: boolean; error?: string }>>({});
  const [editing, setEditing] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState<{ error: boolean; message: string } | null>(null);
  const [downloadUrl, setDownloadUrl] = useState<string | null>(null);
  const nameInputs = useRef<(HTMLInputElement | null)[]>([]);
  const widthInput = useRef<HTMLInputElement>(null);
  const heightInput = useRef<HTMLInputElement>(null);
  const uploadVersions = useRef<number[]>([]);
  const contacts = useMemo(() => people.slice(0, count), [people, count]);
  const selectedContact = editing === null ? null : contacts[editing];
  const dimensions = useMemo(() => parseDimensions(width, height), [width, height]);
  const sheets = useMemo(() => makeSheets(dimensions ?? defaultDimensions, count, setCount), [dimensions, count, setCount]);
  const activePage = Math.min(previewPage, sheets.length - 1);
  const ready = contacts.filter((contact) => contact.name.trim() || contact.photo).length;
  const loading = Object.entries(uploads).some(([index, upload]) => Number(index) < count && upload.loading);
  const uploadError = Object.entries(uploads).some(([index, upload]) => Number(index) < count && upload.error);
  useEffect(() => () => { if (downloadUrl) URL.revokeObjectURL(downloadUrl); }, [downloadUrl]);

  function changeContact(index: number, update: Partial<Contact>) {
    setPeople((current) => current.map((contact, i) => i === index ? { ...contact, ...update } : contact));
    setFeedback(null);
  }

  async function choosePhoto(index: number, file: File) {
    const version = (uploadVersions.current[index] ?? 0) + 1;
    uploadVersions.current[index] = version;
    setUploads((current) => ({ ...current, [index]: { loading: true } }));
    setFeedback(null);
    try {
      const photo = await readPhoto(file);
      if (uploadVersions.current[index] !== version) return;
      changeContact(index, { photo, framing: undefined });
      setUploads((current) => ({ ...current, [index]: {} }));
    } catch (error) {
      if (uploadVersions.current[index] !== version) return;
      setUploads((current) => ({ ...current, [index]: { error: error instanceof Error ? error.message : "Try a different photo." } }));
    }
  }

  function removePhoto(index: number) {
    uploadVersions.current[index] = (uploadVersions.current[index] ?? 0) + 1;
    changeContact(index, { photo: null, framing: undefined });
    setUploads((current) => ({ ...current, [index]: {} }));
  }

  async function download(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || loading) return;
    if (!dimensions) {
      setFeedback({ error: true, message: `Enter a width and height between ${MIN_DIMENSION} and ${MAX_DIMENSION} inches.` });
      (parseDimensions(width, DEFAULT_HEIGHT) ? heightInput : widthInput).current?.focus();
      return;
    }
    const missing = contacts.findIndex(({ name, photo }) => !name.trim() && !photo);
    if (missing !== -1) {
      setFeedback({ error: true, message: `Add a name or photo for Contact ${missing + 1}, or choose fewer contacts.` });
      nameInputs.current[missing]?.focus();
      return;
    }
    if (uploadError) {
      setFeedback({ error: true, message: "One or more photos couldn’t be added. Choose a new photo or dismiss the photo error to continue." });
      return;
    }
    setBusy(true);
    setFeedback(null);
    try {
      const { createLabelPdf } = await import("@/lib/labels/pdf");
      const url = URL.createObjectURL(await createLabelPdf(contacts, dimensions, setCount));
      setDownloadUrl(url);
      saveDownload(url);
      setFeedback({ error: false, message: "PDF ready. Send it to your print shop or print it at Actual Size / 100%." });
    } catch {
      setFeedback({ error: true, message: "The PDF couldn’t be made. Try again, or try smaller photos." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={styles.workspace} onSubmit={download} noValidate aria-busy={busy}>
      <div className={styles.editor} inert={busy}>
        <Step number={1} title="Choose your contacts">
          <div className={styles.contactCount}>
            <p className={styles.hint}>Pick how many people you’d like to put on the phone. Porch uses keys 1–8 for contacts.</p>
            <label className={styles.field} htmlFor="label-count">Number of contacts
              <select id="label-count" value={count} onChange={(event) => { setContactCount(Number(event.target.value)); setPreviewPage(0); setFeedback(null); }}>
                {Array.from({ length: MAX_CONTACTS }, (_, i) => <option key={i + 1} value={i + 1}>{i + 1} {i === 0 ? "contact" : "contacts"}</option>)}
              </select>
            </label>
          </div>
        </Step>
        <Step number={2} title="Add names and photos">
          <p className={styles.hint}>Add a photo, a name, or both for each label. A clear face and a short name work best.</p>
          <div className={styles.contacts}>
            {contacts.map((contact, index) => {
              const upload = uploads[index];
              const label = `Contact ${index + 1}`;
              return (
                <div className={styles.contact} key={index}>
                  <div className={styles.thumb}>
                    {/* Uploaded photos are local data URLs, so they do not pass through the Next image service. */}
                    {contact.photo ? <img src={contact.photo.source} alt="" /> : <Icon name="photo" />}
                  </div>
                  <label className={`${styles.field} ${styles.nameField}`} htmlFor={`label-name-${index}`}>{label} name
                    <input id={`label-name-${index}`} ref={(element) => { nameInputs.current[index] = element; }} value={contact.name} maxLength={48} placeholder={index === 0 ? "e.g. Rose" : "Name"} onChange={(event) => changeContact(index, { name: event.target.value })} />
                  </label>
                  <div className={styles.photoActions}>
                    {contact.photo && <button type="button" className={styles.photoButton} disabled={upload?.loading} onClick={() => setEditing(index)} aria-label={`Preview and adjust photo for ${label}`}>Preview &amp; adjust</button>}
                    <div className={styles.photoLinks}>
                      <label className={contact.photo ? styles.photoLink : styles.photoButton} title={contact.photo?.fileName}>
                        <input type="file" accept={acceptImages} aria-label={`${contact.photo ? "Change" : "Add"} photo for ${label}`} onChange={(event) => {
                          const file = event.currentTarget.files?.[0];
                          event.currentTarget.value = "";
                          if (file) void choosePhoto(index, file);
                        }} />
                        {upload?.loading ? "Opening…" : contact.photo ? "Replace" : "Add photo"}
                      </label>
                      {contact.photo && <button className={styles.textButton} type="button" onClick={() => removePhoto(index)} aria-label={`Remove photo for ${label}`}>Remove</button>}
                    </div>
                  </div>
                  {upload?.error && <div className={styles.uploadError}><p role="alert">{upload.error}</p><button className={styles.textButton} type="button" onClick={() => setUploads((current) => ({ ...current, [index]: {} }))}>Dismiss</button></div>}
                </div>
              );
            })}
          </div>
          <p className={styles.smallNote}>JPG, PNG, or WebP works best. Up to 20 MB per photo.</p>
        </Step>
        <Step number={3} title="Set the label size and quantity">
          <p className={styles.hint} id="label-size-help">Measure the top of a button. Enter the full cutout size, including space for the name.</p>
          <div className={styles.settings}>
            <label className={styles.field} htmlFor="label-width">Width
              <span className={styles.unitField}><input id="label-width" ref={widthInput} type="number" inputMode="decimal" min={MIN_DIMENSION} max={MAX_DIMENSION} step="any" value={width} aria-describedby="label-size-help label-size-range" onChange={(event) => { setWidth(event.target.value); setPreviewPage(0); setFeedback(null); }} /><span>in</span></span>
            </label>
            <label className={styles.field} htmlFor="label-height">Height
              <span className={styles.unitField}><input id="label-height" ref={heightInput} type="number" inputMode="decimal" min={MIN_DIMENSION} max={MAX_DIMENSION} step="any" value={height} aria-describedby="label-size-help label-size-range" onChange={(event) => { setHeight(event.target.value); setPreviewPage(0); setFeedback(null); }} /><span>in</span></span>
            </label>
            <label className={styles.field} htmlFor="label-sets">Sets to print
              <select id="label-sets" aria-describedby="label-sets-help" value={setCount} onChange={(event) => { setSetCount(Number(event.target.value)); setPreviewPage(0); setFeedback(null); }}>
                {Array.from({ length: MAX_SETS }, (_, i) => <option key={i + 1} value={i + 1}>{i + 1} {i === 0 ? "set" : "sets"}</option>)}
              </select>
            </label>
          </div>
          <div className={styles.sizeNote}>
            <p className={styles.smallNote} id="label-size-range">Each side can be {MIN_DIMENSION}–{MAX_DIMENSION} inches.</p>
            <button type="button" className={styles.textButton} onClick={() => { setWidth(DEFAULT_WIDTH); setHeight(DEFAULT_HEIGHT); setPreviewPage(0); setFeedback(null); }}>Use 1 × 1.5 in</button>
          </div>
          <p className={styles.smallNote} id="label-sets-help">One set includes one label for each contact.</p>
        </Step>
      </div>
      <aside className={styles.review} aria-label="Print preview and download">
        <div className={styles.reviewHeader}>
          <div><h2>Print preview</h2><p>US Letter · 8.5 × 11 in</p></div>
          <span className={styles.sizePill}>{dimensions ? formatSize(dimensions) : "Check size"}</span>
        </div>
        <div className={styles.previewFrame}>
          {dimensions ? <Preview contacts={contacts} pages={sheets} dimensions={dimensions} page={activePage} />
            : <p className={styles.previewError}>Enter a width and height from {MIN_DIMENSION} to {MAX_DIMENSION} inches to see your sheet.</p>}
        </div>
        {sheets.length > 1 && dimensions && <div className={styles.pagination} aria-label="Preview pages">
          <button type="button" aria-label="Previous preview page" disabled={activePage === 0} onClick={() => setPreviewPage(activePage - 1)}><Icon name="chevron" /></button>
          <span>Page {activePage + 1} of {sheets.length}</span>
          <button type="button" aria-label="Next preview page" disabled={activePage === sheets.length - 1} onClick={() => setPreviewPage(activePage + 1)}><Icon name="chevron" /></button>
        </div>}
        <div className={styles.downloadArea}>
          <div className={styles.progress}><span>{ready} of {count} contacts ready</span>{dimensions && <span>{count * setCount} {count * setCount === 1 ? "label" : "labels"} · {sheets.length} {sheets.length === 1 ? "page" : "pages"}</span>}</div>
          <button type="submit" className={styles.download} disabled={busy || loading}><Icon name="download" />{busy ? "Making your PDF…" : loading ? "Opening photos…" : "Download print-ready PDF"}</button>
          {feedback && <p role={feedback.error ? "alert" : "status"} className={feedback.error ? styles.error : styles.success}>{feedback.message}</p>}
          {feedback && !feedback.error && downloadUrl && <a className={styles.textButton} href={downloadUrl} download="porch-phone-labels.pdf">Save PDF again</a>}
          <p className={styles.smallNote}>Send the PDF to a print shop, or print in color at <strong>Actual Size / 100%</strong>. Cut along the corner marks.</p>
        </div>
        <p className={styles.privacy}><Icon name="lock" /> Names and photos stay in your browser.</p>
      </aside>
      {editing !== null && selectedContact?.photo && <PhotoEditor
        key={editing}
        contact={{ ...selectedContact, photo: selectedContact.photo }}
        dimensions={dimensions ?? defaultDimensions}
        contactNumber={editing + 1}
        onCancel={() => setEditing(null)}
        onSave={(framing) => { changeContact(editing, { framing }); setEditing(null); }}
      />}
    </form>
  );
}
