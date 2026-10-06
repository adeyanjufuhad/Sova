"use client";

// Fade-up on scroll, in the style of Magic UI "Blur Fade" (as listed on 21st.dev),
// without the blur to keep the flat look. Instant for reduced-motion users.
// The markup is the same either way: swapping in a plain div after hydration
// would keep the server's opacity:0 and leave the content invisible.
import { motion, useReducedMotion } from "motion/react";

export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: React.ReactNode;
  delay?: number;
  className?: string;
}) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={reduce ? { duration: 0 } : { duration: 0.6, delay, ease: [0.21, 0.47, 0.32, 0.98] }}
    >
      {children}
    </motion.div>
  );
}
