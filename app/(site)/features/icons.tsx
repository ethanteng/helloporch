// Small line icons for the story scenes, drawn on a 24-point grid in the current text color.
type IconProps = { className?: string };

function Icon({ className, children }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export function PlayIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 12 12" className={className} aria-hidden="true">
      <path d="M3 1.5v9l7.5-4.5z" fill="currentColor" />
    </svg>
  );
}

export function VideoIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <rect x="2.5" y="6" width="13" height="12" rx="3" />
      <path d="M15.5 10.5 21 7.5v9l-5.5-3" />
    </Icon>
  );
}

export function PhoneIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M5 3.5h3.2l1.6 4.2-2.1 1.4a11 11 0 0 0 7.2 7.2l1.4-2.1 4.2 1.6V19a2 2 0 0 1-2 2A16.5 16.5 0 0 1 3 5.5a2 2 0 0 1 2-2z" />
    </Icon>
  );
}

export function SpeakerIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" />
      <path d="M15.5 9a4.2 4.2 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11" />
    </Icon>
  );
}

export function EyeIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" />
      <circle cx="12" cy="12" r="3" />
    </Icon>
  );
}

export function AddPersonIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <circle cx="9.5" cy="8" r="3.5" />
      <path d="M3 20c.6-3.6 3.2-5.5 6.5-5.5s5.9 1.9 6.5 5.5M19 8v6M16 11h6" />
    </Icon>
  );
}

export function BankIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M3 9.5 12 4l9 5.5zM5 10v7M9.5 10v7M14.5 10v7M19 10v7M3 20h18" />
    </Icon>
  );
}

export function MicOffIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M4 4l16 16" />
    </Icon>
  );
}

export function EndCallIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M3 14.5c0-2.5 4-4.5 9-4.5s9 2 9 4.5l-.3 1.3a1.5 1.5 0 0 1-1.8 1l-2.7-.7a1.5 1.5 0 0 1-1.1-1.4v-1.4a13 13 0 0 0-6.2 0v1.4a1.5 1.5 0 0 1-1.1 1.4l-2.7.7a1.5 1.5 0 0 1-1.8-1z" />
    </Icon>
  );
}

export function SendIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M21 3 10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5z" />
    </Icon>
  );
}

export function ShieldIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M12 3 4.5 6v5.5c0 4.6 3.1 8.2 7.5 9.5 4.4-1.3 7.5-4.9 7.5-9.5V6z" />
      <path d="m8.8 12 2.3 2.3 4.3-4.6" />
    </Icon>
  );
}

export function CloseIcon({ className }: IconProps) {
  return (
    <Icon className={className}>
      <path d="M6 6l12 12M18 6 6 18" />
    </Icon>
  );
}
