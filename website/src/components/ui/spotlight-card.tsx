"use client";

// Mouse-follow glow card, adapted from Aceternity UI "Card Spotlight" (as listed on 21st.dev)
// without the WebGL canvas, so it stays light on low-end phones.
import { motion, useMotionTemplate, useMotionValue } from "motion/react";
import { cn } from "@/lib/utils";

export function SpotlightCard({
  children,
  className,
  radius = 320,
  color = "rgba(29, 78, 216, 0.07)",
}: {
  children: React.ReactNode;
  className?: string;
  radius?: number;
  color?: string;
}) {
  const x = useMotionValue(-radius);
  const y = useMotionValue(-radius);
  const background = useMotionTemplate`radial-gradient(${radius}px circle at ${x}px ${y}px, ${color}, transparent 80%)`;

  return (
    <div
      onMouseMove={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        x.set(e.clientX - r.left);
        y.set(e.clientY - r.top);
      }}
      className={cn(
        "group/card relative overflow-hidden rounded-3xl border border-navy-900/[0.08] bg-white p-6 shadow-[0_1px_2px_rgba(11,26,51,0.04),0_12px_32px_-16px_rgba(11,26,51,0.12)] transition-colors hover:border-electric/25",
        className,
      )}
    >
      <motion.div
        className="pointer-events-none absolute -inset-px rounded-3xl opacity-0 transition duration-300 group-hover/card:opacity-100"
        style={{ background }}
      />
      <div className="relative h-full">{children}</div>
    </div>
  );
}
