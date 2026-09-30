import { Logo } from "@/components/ui/logo";
import { site } from "@/lib/site";

export function Footer() {
  return (
    <footer className="relative border-t border-navy-900/10 bg-white px-4 pt-16 pb-10">
      <div className="mx-auto max-w-6xl">
        <div className="flex flex-col justify-between gap-10 md:flex-row">
          <div className="max-w-sm">
            <Logo variant="navy" />
            <p className="mt-4 text-sm text-slate-500">
              Records, reminders and receipts for ajo, esusu and adashe circles. Built in Nigeria.
            </p>
          </div>
          <nav className="grid grid-cols-2 gap-x-16 gap-y-3 text-sm">
            {site.nav.map((n) => (
              <a key={n.href} href={n.href} className="text-slate-600 transition hover:text-electric">
                {n.label}
              </a>
            ))}
            <a href="#waitlist" className="text-slate-600 transition hover:text-electric">
              Waitlist
            </a>
          </nav>
        </div>

        <div className="mt-14 flex flex-col gap-4 border-t border-navy-900/10 pt-8 text-xs text-slate-500 sm:flex-row sm:items-center sm:justify-between">
          <p>© {new Date().getFullYear()} Sova. All rights reserved.</p>
          <p className="max-w-md sm:text-right">
            Sova is a record-keeping tool, not a bank. We never hold or invest members&apos; money.
          </p>
        </div>
      </div>

      {/* oversized wordmark */}
      <p
        aria-hidden
        className="pointer-events-none mt-10 select-none text-center font-display text-[28vw] font-semibold leading-none tracking-tighter text-electric/[0.05] sm:text-[22vw]"
      >
        sova
      </p>
    </footer>
  );
}
