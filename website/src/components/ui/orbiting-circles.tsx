"use client";

// "Orbiting Circles 02" (via 21st.dev), adapted for Sova: items are any React
// node (icons or text labels) instead of remote logo images, colours use Sova
// tokens, and the centre globe is our own ParticleSphere.
import { ParticleSphere } from "./particle-sphere";

export type Orbit = {
  /** Tailwind size classes for the ring */
  size: string;
  /** seconds per revolution */
  duration: number;
  items: { id: string; content: React.ReactNode; angle: number }[];
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

      {/* Centre globe, half below the bottom edge */}
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
            {orbit.items.map(({ id, content, angle }) => (
              // Zero-width arm from the ring's centre to its top edge; the item
              // sits centred on the arm's tip and counter-rotates to stay upright.
              <div
                key={id}
                className="absolute left-1/2 top-0 flex h-1/2 w-0 origin-bottom flex-col items-center justify-start"
                style={
                  {
                    "--start-angle": `${angle}deg`,
                    animation: `${orbitAnim} ${orbit.duration}s linear infinite`,
                  } as React.CSSProperties
                }
              >
                <div
                  className="relative z-10 -mt-5 shrink-0"
                  style={
                    {
                      "--counter-offset": `${-angle}deg`,
                      animation: `${counterAnim} ${orbit.duration}s linear infinite`,
                    } as React.CSSProperties
                  }
                >
                  {content}
                </div>
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
}
