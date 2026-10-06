import { cn } from "@/lib/utils";
import { Reveal } from "./reveal";

/**
 * Section opener. "split" (default) sets a large headline on the left and the
 * supporting text on the right, bottom-aligned; it stacks on phones. "center"
 * is for narrow or radial sections (the FAQ, the orbit of names).
 */
export function SectionHeading({
  eyebrow,
  title,
  sub,
  className,
  tone = "light",
  align = "split",
}: {
  eyebrow: string;
  title: React.ReactNode;
  sub?: React.ReactNode;
  className?: string;
  tone?: "dark" | "light";
  align?: "split" | "center";
}) {
  const eyebrowEl = (
    <p
      className={cn(
        "inline-flex items-center gap-2 text-sm font-semibold",
        tone === "dark" ? "text-sky-300" : "text-electric",
      )}
    >
      {eyebrow}
    </p>
  );
  const titleEl = (
    <h2
      className={cn(
        "mt-4 font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-balance sm:text-6xl",
        tone === "dark" ? "text-white" : "text-navy-900",
      )}
    >
      {title}
    </h2>
  );
  const subEl = sub && (
    <p className={cn("text-base text-pretty sm:text-lg", tone === "dark" ? "text-white/75" : "text-slate-600")}>{sub}</p>
  );

  if (align === "center") {
    return (
      <Reveal className={cn("mx-auto max-w-2xl text-center", className)}>
        {eyebrowEl}
        {titleEl}
        {subEl && <div className="mt-4">{subEl}</div>}
      </Reveal>
    );
  }

  return (
    <Reveal className={cn("grid gap-6 lg:grid-cols-12 lg:items-end lg:gap-10", className)}>
      <div className="lg:col-span-7">
        {eyebrowEl}
        {titleEl}
      </div>
      {subEl && <div className="max-w-[46ch] lg:col-span-5 lg:pb-2">{subEl}</div>}
    </Reveal>
  );
}
