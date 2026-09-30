import { cn } from "@/lib/utils";
import { Reveal } from "./reveal";

export function SectionHeading({
  eyebrow,
  title,
  sub,
  className,
  tone = "dark",
}: {
  eyebrow: string;
  title: React.ReactNode;
  sub?: React.ReactNode;
  className?: string;
  tone?: "dark" | "light";
}) {
  return (
    <Reveal className={cn("mx-auto max-w-2xl text-center", className)}>
      <p
        className={cn(
          "font-mono text-xs uppercase tracking-[0.2em]",
          tone === "dark" ? "text-sky" : "text-electric",
        )}
      >
        {eyebrow}
      </p>
      <h2
        className={cn(
          "mt-4 font-display text-3xl font-semibold tracking-tight text-balance sm:text-5xl",
          tone === "dark" ? "text-white" : "text-navy-900",
        )}
      >
        {title}
      </h2>
      {sub && (
        <p
          className={cn(
            "mt-4 text-base text-pretty sm:text-lg",
            tone === "dark" ? "text-slate-300" : "text-navy-700/80",
          )}
        >
          {sub}
        </p>
      )}
    </Reveal>
  );
}
