"use client";

// Aceternity UI "Timeline" (via 21st.dev), flattened for Sova: solid blue
// progress line, heading passed in as props, tighter spacing.
import { motion, useScroll, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

export interface TimelineEntry {
  title: string;
  content: React.ReactNode;
}

export function Timeline({
  data,
  heading,
  className,
}: {
  data: TimelineEntry[];
  heading?: React.ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => setHeight(el.getBoundingClientRect().height);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const { scrollYProgress } = useScroll({ target: containerRef, offset: ["start 10%", "end 50%"] });
  const heightTransform = useTransform(scrollYProgress, [0, 1], [0, height]);

  return (
    <div className={cn("w-full", className)} ref={containerRef}>
      {heading && <div className="mx-auto max-w-6xl px-4 pb-6">{heading}</div>}

      <div ref={ref} className="relative mx-auto max-w-6xl pb-10">
        {data.map((item) => (
          <div key={item.title} className="flex justify-start pt-10 md:gap-10 md:pt-20">
            <div className="sticky top-32 z-40 flex max-w-xs flex-col items-center self-start md:w-full md:flex-row lg:max-w-sm">
              <div className="absolute left-3 flex size-10 items-center justify-center rounded-full bg-white">
                <div className="size-4 rounded-full border-2 border-electric bg-white" />
              </div>
              <h3 className="hidden font-display text-3xl font-semibold text-navy-900/40 md:block md:pl-20 lg:text-4xl">
                {item.title}
              </h3>
            </div>

            <div className="relative w-full pl-20 pr-4 md:pl-4">
              <h3 className="mb-4 block text-left font-display text-2xl font-semibold text-navy-900/40 md:hidden">
                {item.title}
              </h3>
              {item.content}
            </div>
          </div>
        ))}

        {/* Track + solid blue progress line */}
        <div style={{ height }} className="absolute left-8 top-0 w-0.5 overflow-hidden bg-navy-900/10">
          <motion.div style={{ height: heightTransform }} className="absolute inset-x-0 top-0 w-0.5 bg-electric" />
        </div>
      </div>
    </div>
  );
}
