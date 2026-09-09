import Link from "next/link";
export function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={compact ? "mini-mark" : "brand-mark"} aria-hidden="true">
      <svg viewBox="0 0 32 32">
        <path d="M5 14v4m5-8v12m6-17v22m6-17v12m5-8v4" />
      </svg>
    </span>
  );
}
export function Brand() {
  return (
    <Link href="/" className="brand" aria-label="Voice Notes home">
      <BrandMark />
      Voice Notes
    </Link>
  );
}
export function Waveform() {
  return (
    <div className="waveform" aria-hidden="true">
      {[
        16, 26, 12, 36, 52, 24, 40, 66, 44, 82, 57, 36, 70, 98, 68, 45, 85, 56,
        34, 61, 43, 24, 47, 31, 18, 32, 16, 22,
      ].map((h, i) => (
        <i
          key={i}
          style={
            {
              "--bar": `${h}%`,
              "--delay": `${i * 35}ms`,
            } as React.CSSProperties
          }
        />
      ))}
    </div>
  );
}
