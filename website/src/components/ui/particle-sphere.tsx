"use client";

// Rotating dot globe drawn on a 2D canvas. Written for Sova because the
// 21st.dev orbiting-circles prompt referenced this file without including it.
// Flat style: solid blue dots, depth shown only by dot size and opacity.
import { useEffect, useRef } from "react";

export function ParticleSphere({
  points = 700,
  color = "29, 78, 216",
  speed = 0.0025,
}: {
  points?: number;
  /** RGB triplet, e.g. "29, 78, 216" */
  color?: string;
  speed?: number;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;

    // Evenly spread points on a unit sphere (Fibonacci lattice).
    const golden = Math.PI * (3 - Math.sqrt(5));
    const pts = Array.from({ length: points }, (_, i) => {
      const y = 1 - (i / (points - 1)) * 2;
      const r = Math.sqrt(1 - y * y);
      const t = golden * i;
      return [Math.cos(t) * r, y, Math.sin(t) * r] as const;
    });

    let size = 0;
    let dpr = 1;
    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      size = canvas.clientWidth;
      canvas.width = size * dpr;
      canvas.height = size * dpr;
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    const tilt = 0.35;
    const cosT = Math.cos(tilt);
    const sinT = Math.sin(tilt);
    let angle = 0;
    let frame = 0;
    let running = false;

    const draw = () => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, size, size);
      const radius = size * 0.46;
      const c = size / 2;
      const cosA = Math.cos(angle);
      const sinA = Math.sin(angle);
      for (const [x, y, z] of pts) {
        // spin around Y, then tilt around X
        const x1 = x * cosA - z * sinA;
        const z1 = x * sinA + z * cosA;
        const y2 = y * cosT - z1 * sinT;
        const z2 = y * sinT + z1 * cosT;
        const depth = (z2 + 1) / 2; // 0 back, 1 front
        ctx.fillStyle = `rgba(${color}, ${0.12 + depth * 0.6})`;
        ctx.beginPath();
        ctx.arc(c + x1 * radius, c + y2 * radius, 0.6 + depth * 1.4, 0, Math.PI * 2);
        ctx.fill();
      }
    };

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const loop = () => {
      angle += speed;
      draw();
      frame = requestAnimationFrame(loop);
    };

    // Only animate while visible.
    const io = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && !running && !reduced) {
        running = true;
        frame = requestAnimationFrame(loop);
      } else if (!entry.isIntersecting && running) {
        running = false;
        cancelAnimationFrame(frame);
      }
    });
    io.observe(canvas);
    draw();

    return () => {
      cancelAnimationFrame(frame);
      io.disconnect();
      ro.disconnect();
    };
  }, [points, color, speed]);

  return <canvas ref={canvasRef} className="size-full" aria-hidden />;
}
