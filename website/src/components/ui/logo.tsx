import Image from "next/image";
import { cn } from "@/lib/utils";

export function Logo({
  variant = "light",
  className,
  withWordmark = true,
}: {
  variant?: "light" | "navy";
  className?: string;
  withWordmark?: boolean;
}) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <Image
        src={variant === "light" ? "/brand/sova-mark-light.png" : "/brand/sova-mark-navy.png"}
        alt={withWordmark ? "" : "Sova"}
        width={32}
        height={32}
        className="size-8"
        priority
      />
      {withWordmark && (
        <span
          className={cn(
            "font-display text-xl font-semibold tracking-tight",
            variant === "light" ? "text-white" : "text-navy-900",
          )}
        >
          sova
        </span>
      )}
    </span>
  );
}
