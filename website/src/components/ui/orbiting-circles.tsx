"use client";

// "Orbiting Circles 02" (via 21st.dev), adapted for Sova: icons are passed in
// as lucide components instead of remote logo images, colours use Sova tokens,
// and the centre globe is our own ParticleSphere.
import type { LucideIcon } from "lucide-react";
import { ParticleSphere } from "./particle-sphere";

export type Orbit = {
  /** Tailwind size classes for the ring */
  size: string;
  /** seconds per revolution */
  duration: number;
  icons: { icon: LucideIcon; label: string; angle: number }[];
};

export function OrbitingCircles({ orbits }: { orbits: Orbit[] }) {
  return (
    <div className="relative flex h-110 w-full justify-center overflow-hidden md:h-160">
      <style>{`
        @keyframes orbit-cw { from { transform: rotate(var(--start-angle)) } to { transform: rotate(calc(var(--start-angle) + 360deg)) } }
        @keyframes orbit-ccw { from { transform: rotate(var(--start-angle)) } to { transform: rotate(calc(var(--start-angle) - 360deg)) } }
        @keyframes counter-cw { from { transform: rotate(var(--counter-offset, 0deg)) } to { transform: rotate(calc(var(--counter-offset, 0deg) - 360deg)) } }
        @keyframes counter-ccw { from { transform: rotate(var(--counter-offset, 0deg)) } to { transform: rotate(calc(var(--counter-offset, 0deg) + 360deg)) } }
      `}</style>

      {/* Centre globe, half below the fold of the section */}
      <div className="pointer-events-none absolute bottom-0 left-1/2 z-10 aspect-square w-75 -translate-x-1/2 translate-y-1/2 md:w-145">
        <ParticleSphere />
      </div>

      {orbits.map((orbit, index) => {
        const isCW = index % 2 === 0;
        const orbitAnim = isCW ? "orbit-cw" : "orbit-ccw";
        const counterAnim = isCW ? "counter-cw" : "counter-ccw";

        return (
          <div
            key={index}
            className={`absolute bottom-0 left-1/2 -translate-x-1/2 translate-y-1/2 rounded-full border border-navy-900/10 ${orbit.size}`}
          >
            {orbit.icons.map(({ icon: Icon, label, angle }) => (
              <div
                key={label}
                className="absolute left-1/2 top-0 -ml-8 flex h-1/2 origin-bottom flex-col items-center justify-start"
                style={
                  {
                    "--start-angle": `${angle}deg`,
                    animation: `${orbitAnim} ${orbit.duration}s linear infinite`,
                  } as React.CSSProperties
                }
              >
                <div
                  title={label}
                  className="relative z-10 -mt-8 rounded-full border border-navy-900/10 bg-white p-3 text-electric sm:p-4"
                  style={
                    {
                      "--counter-offset": `${-angle}deg`,
                      animation: `${counterAnim} ${orbit.duration}s linear infinite`,
                    } as React.CSSProperties
                  }
                >
                  <Icon className="size-6 md:size-8" strokeWidth={1.75} aria-label={label} />
                </div>
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
}
