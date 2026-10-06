import { ArrowRight, ShieldCheck } from "lucide-react";
import { AdireStrip } from "@/components/ui/adire";
import { Logo } from "@/components/ui/logo";
import { site } from "@/lib/site";

// Navy closing band: a plain invitation first, then the links, the safety note
// and the legal disclosure.
export function Footer() {
  return (
    <footer className="bg-navy-900 text-white">
      <AdireStrip id="footer-strip" className="text-sky/25" />

      <div className="px-4 pt-20 pb-12 sm:pt-24">
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-8 border-b border-white/10 pb-14 lg:grid-cols-12 lg:items-end">
            <h2 className="font-display text-4xl font-extrabold leading-[1.02] tracking-[-0.03em] text-balance sm:text-6xl lg:col-span-8">
              Your circle already runs on trust. <span className="text-sky">Give it a record.</span>
            </h2>
            <div className="lg:col-span-4 lg:justify-self-end">
              <a
                href={site.appUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="group inline-flex items-center gap-2 rounded-2xl bg-white px-6 py-4 font-semibold text-navy-900 transition-colors hover:bg-mist active:scale-[0.98]"
              >
                Try the live demo
                <ArrowRight aria-hidden className="size-4 transition-transform group-hover:translate-x-0.5" />
              </a>
            </div>
          </div>

          <div className="grid gap-10 pt-12 md:grid-cols-[1.4fr_1fr_1fr]">
            <div className="max-w-sm">
              <Logo variant="light" />
              <p className="mt-4 text-sm text-white/65">
                Records, reminders and receipts for ajo, esusu and adashe circles. Built in Nigeria.
              </p>
            </div>

            <nav aria-label="Footer">
              <p className="text-sm font-semibold text-sky-300">Sova</p>
              <ul className="mt-4 space-y-2.5 text-sm">
                {[...site.nav, { label: "Join the waitlist", href: "#waitlist" }].map((n) => (
                  <li key={n.href}>
                    <a href={n.href} className="text-white/75 transition-colors hover:text-white">
                      {n.label}
                    </a>
                  </li>
                ))}
              </ul>
            </nav>

            <div>
              <p className="text-sm font-semibold text-sky-300">Stay safe</p>
              <p className="mt-4 flex gap-2 text-sm text-white/75">
                <ShieldCheck aria-hidden className="mt-0.5 size-4 shrink-0 text-sky" />
                Sova will never call or text to ask for your PIN, OTP or bank password. If someone does, it is not us.
              </p>
            </div>
          </div>

          <div className="mt-12 flex flex-col gap-3 border-t border-white/10 pt-6 text-xs text-white/50 sm:flex-row sm:items-start sm:justify-between">
            <p>© {new Date().getFullYear()} Sova. All rights reserved.</p>
            <p className="max-w-lg sm:text-right">
              Sova is a record-keeping service, not a bank, lender or wallet. We never hold, lend or invest members&apos;
              money. Contributions move directly between members.
            </p>
          </div>
        </div>
      </div>
    </footer>
  );
}
