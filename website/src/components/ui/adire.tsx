import { cn } from "@/lib/utils";

/*
 * Flat line patterns inspired by adire, the Yoruba indigo-and-white
 * resist-dyed cloth: oniko tie-dye circles, dotted fields, lafun-style
 * diamonds and river waves. Colour comes from `currentColor`, so set it
 * with a text colour class (e.g. "text-white/10" on blue).
 *
 * `id` must be unique on the page (it names the SVG pattern).
 */
export function AdirePattern({ id, className }: { id: string; className?: string }) {
  return (
    <svg aria-hidden className={cn("pointer-events-none absolute inset-0 size-full", className)}>
      <defs>
        <pattern id={id} width="120" height="120" patternUnits="userSpaceOnUse">
          <g fill="none" stroke="currentColor" strokeWidth="1.5">
            {/* oniko circles */}
            <circle cx="30" cy="30" r="22" />
            <circle cx="30" cy="30" r="14" />
            <circle cx="30" cy="30" r="6" />
            {/* lafun diamond with cross */}
            <path d="M30 66 L54 90 L30 114 L6 90 Z" />
            <path d="M30 74 V106 M14 90 H46" />
            {/* river waves */}
            <path d="M60 76 q7.5 -8 15 0 t15 0 t15 0 t15 0" />
            <path d="M60 90 q7.5 -8 15 0 t15 0 t15 0 t15 0" />
            <path d="M60 104 q7.5 -8 15 0 t15 0 t15 0 t15 0" />
          </g>
          {/* dotted field */}
          <g fill="currentColor">
            {[72, 90, 108].flatMap((x) =>
              [12, 30, 48].map((y) => <circle key={`${x}-${y}`} cx={x} cy={y} r="2.5" />),
            )}
          </g>
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={`url(#${id})`} />
    </svg>
  );
}

/** A thin repeating adire border, used as a divider. */
export function AdireStrip({ id, className }: { id: string; className?: string }) {
  return (
    <svg aria-hidden className={cn("block h-7 w-full", className)}>
      <defs>
        <pattern id={id} width="56" height="28" patternUnits="userSpaceOnUse">
          <g fill="none" stroke="currentColor" strokeWidth="1.5">
            <circle cx="14" cy="14" r="8" />
            <circle cx="14" cy="14" r="3" />
            <path d="M42 7 L49 14 L42 21 L35 14 Z" />
          </g>
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={`url(#${id})`} />
    </svg>
  );
}
