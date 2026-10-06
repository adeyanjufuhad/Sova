import { cn } from "@/lib/utils";

// Flat card: white fill, hairline border; on hover the border turns blue and
// the card lifts 2px (transform only, no shadow).
export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        "rounded-3xl border border-navy-900/10 bg-white p-6 transition duration-200 hover:-translate-y-0.5 hover:border-electric/40",
        className,
      )}
    >
      {children}
    </div>
  );
}
