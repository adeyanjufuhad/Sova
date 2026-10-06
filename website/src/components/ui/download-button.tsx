import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

function AndroidGlyph({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className={className}>
      <path d="M17.6 9.48l1.84-3.18a.38.38 0 00-.66-.38l-1.87 3.23A11.4 11.4 0 0012 8.1c-1.76 0-3.42.39-4.9 1.05L5.22 5.92a.38.38 0 00-.66.38L6.4 9.48A10.8 10.8 0 001 18h22a10.8 10.8 0 00-5.4-8.52zM7 15.25a1.25 1.25 0 110-2.5 1.25 1.25 0 010 2.5zm10 0a1.25 1.25 0 110-2.5 1.25 1.25 0 010 2.5z" />
    </svg>
  );
}

/**
 * Points to Google Play once NEXT_PUBLIC_PLAY_STORE_URL is set.
 * Until then it's an honest "coming soon" that scrolls to the waitlist.
 */
export function DownloadButton({
  className,
  tone = "light",
}: {
  className?: string;
  tone?: "light" | "blue";
}) {
  const live = Boolean(site.playStoreUrl);
  return (
    <a
      href={live ? site.playStoreUrl : "#waitlist"}
      {...(live ? { target: "_blank", rel: "noopener noreferrer" } : {})}
      className={cn(
        "group inline-flex items-center gap-3 rounded-2xl border px-5 py-3 text-left transition active:scale-[0.98]",
        tone === "light"
          ? "border-navy-900/15 bg-white text-navy-900 hover:border-electric/40 hover:bg-mist"
          : "border-white/20 bg-white/10 text-white hover:bg-white/15",
        className,
      )}
    >
      <AndroidGlyph className={cn("size-6", tone === "light" ? "text-electric" : "text-white")} />
      <span className="leading-tight">
        <span className={cn("block text-[11px] uppercase tracking-wider", tone === "light" ? "text-slate-500" : "text-white/60")}>
          {live ? "Get it on" : "Coming soon to"}
        </span>
        <span className="block font-medium">Google Play</span>
      </span>
      {!live && (
        <span
          className={cn(
            "ml-1 rounded-full px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider",
            tone === "light" ? "bg-electric/10 text-electric" : "bg-white/15 text-white",
          )}
        >
          Soon
        </span>
      )}
    </a>
  );
}
