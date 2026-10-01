import { ShieldCheck } from "lucide-react";
import { AdireStrip } from "@/components/ui/adire";
import { Logo } from "@/components/ui/logo";
import { site } from "@/lib/site";

export function Footer() {
  return (
    <footer className="bg-white">
      <AdireStrip id="footer-strip" className="text-electric/30" />

      <div className="border-t border-navy-900/10 px-4 pt-14 pb-10">
        <div className="mx-auto max-w-6xl">
          <div className="grid gap-10 md:grid-cols-[1.4fr_1fr_1fr]">
            <div className="max-w-sm">
              <Logo variant="navy" />
              <p className="mt-4 text-sm text-slate-600">
                Records, reminders and receipts for ajo, esusu and adashe circles. Built in Nigeria.
              </p>
            </div>

            <nav aria-label="Footer">
              <p className="text-sm font-semibold text-navy-900">Sova</p>
              <ul className="mt-3 space-y-2.5 text-sm">
                {[...site.nav, { label: "Join the waitlist", href: "#waitlist" }].map(
                  (n) => (
                    <li key={n.href}>
                      <a href={n.href} className="text-slate-600 transition hover:text-electric">
                        {n.label}
                      </a>
                    </li>
                  ),
                )}
              </ul>
            </nav>

            <div>
              <p className="text-sm font-semibold text-navy-900">Stay safe</p>
              <p className="mt-3 flex gap-2 text-sm text-slate-600">
                <ShieldCheck className="mt-0.5 size-4 shrink-0 text-electric" />
                Sova will never call or text to ask for your PIN, OTP or bank password. If someone does, it is not
                us.
              </p>
            </div>
          </div>

          <div className="mt-12 flex flex-col gap-3 border-t border-navy-900/10 pt-6 text-xs text-slate-500 sm:flex-row sm:items-start sm:justify-between">
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
