"use client";

// Mouse-follow glow card, adapted from Aceternity UI "Card Spotlight" (as listed on 21st.dev)
// without the WebGL canvas, so it stays light on low-end phones.
import { motion, useMotionTemplate, useMotionValue } from "motion/react";
import { cn } from "@/lib/utils";

export function SpotlightCard({
  children,
  className,
  radius = 320,
  color = "rgba(59, 106, 232, 0.14)",
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
        "group/card relative overflow-hidden rounded-3xl border border-white/10 bg-navy-900/60 p-6 transition-colors hover:border-white/20",
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
