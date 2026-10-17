/* The Porch logo: a smiling "p" mark beside the "porch" wordmark. The parent's
   `.logo`-style rule sets the font and size; `.logo__mark` colors the mark. */
export default function PorchLogo() {
  return (
    <>
      <svg className="logo__mark" viewBox="11 7.5 82 88" aria-hidden>
        <g fill="none" stroke="currentColor" strokeWidth="9" strokeLinecap="round">
          <line x1="20" y1="44" x2="20" y2="91" />
          <circle cx="52" cy="44" r="32" />
          <path d="M36 42 Q52 60 68 42" />
        </g>
      </svg>
      porch
    </>
  );
}
