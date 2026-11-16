/** A "?" button that opens a short note beside it. It is the browser's own popover, so it works without a script, and
 * Escape or a click elsewhere closes it. Where the note sits is in admin.css, by its `id`. */
export default function Help({ id, label, end, children }: { id: string; label: string; end?: boolean; children: React.ReactNode }) {
  return (
    <>
      <button type="button" className="help" id={`${id}-button`} popoverTarget={id} aria-label={label}><span aria-hidden="true">?</span></button>
      <div id={id} popover="auto" className={end ? "pop end" : "pop"}>{children}</div>
    </>
  );
}
