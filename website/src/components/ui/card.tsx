import { cn } from "@/lib/utils";

// Flat card: white fill, hairline border, border turns blue on hover.
export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        "rounded-3xl border border-navy-900/10 bg-white p-6 transition-colors hover:border-electric/40",
        className,
      )}
    >
      {children}
    </div>
  );
}
