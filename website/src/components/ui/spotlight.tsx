"use client";

// Adapted from Aceternity UI "Spotlight" (as listed on 21st.dev), recoloured for Sova.
import { motion } from "motion/react";

type SpotlightProps = {
  gradientFirst?: string;
  gradientSecond?: string;
  gradientThird?: string;
  translateY?: number;
  width?: number;
  height?: number;
  smallWidth?: number;
  duration?: number;
  xOffset?: number;
};

export function Spotlight({
  gradientFirst = "radial-gradient(68.54% 68.72% at 55.02% 31.46%, hsla(222, 100%, 80%, .12) 0, hsla(222, 100%, 60%, .04) 50%, hsla(222, 100%, 50%, 0) 80%)",
  gradientSecond = "radial-gradient(50% 50% at 50% 50%, hsla(199, 70%, 80%, .08) 0, hsla(199, 70%, 60%, .02) 80%, transparent 100%)",
  gradientThird = "radial-gradient(50% 50% at 50% 50%, hsla(199, 70%, 80%, .05) 0, hsla(222, 100%, 50%, .02) 80%, transparent 100%)",
  translateY = -350,
  width = 560,
  height = 1380,
  smallWidth = 240,
  duration = 7,
  xOffset = 100,
}: SpotlightProps) {
  const beams = (side: "left" | "right") => {
    const sign = side === "left" ? 1 : -1;
    const anchor = side === "left" ? "left-0 origin-top-left" : "right-0 origin-top-right";
    return (
      <motion.div
        animate={{ x: [0, sign * xOffset, 0] }}
        transition={{ duration, repeat: Infinity, repeatType: "reverse", ease: "easeInOut" }}
        className={`pointer-events-none absolute top-0 h-full w-full ${side === "left" ? "left-0" : "right-0"}`}
      >
        <div
          style={{
            transform: `translateY(${translateY}px) rotate(${sign * -45}deg)`,
            background: gradientFirst,
            width,
            height,
          }}
          className={`absolute top-0 ${side === "left" ? "left-0" : "right-0"}`}
        />
        <div
          style={{
            transform: `rotate(${sign * -45}deg) translate(${sign * 5}%, -50%)`,
            background: gradientSecond,
            width: smallWidth,
            height,
          }}
          className={`absolute top-0 ${anchor}`}
        />
        <div
          style={{
            transform: `rotate(${sign * -45}deg) translate(${sign * -180}%, -70%)`,
            background: gradientThird,
            width: smallWidth,
            height,
          }}
          className={`absolute top-0 ${anchor}`}
        />
      </motion.div>
    );
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 1.5 }}
      className="pointer-events-none absolute inset-0 h-full w-full overflow-hidden"
    >
      {beams("left")}
      {beams("right")}
    </motion.div>
  );
}
