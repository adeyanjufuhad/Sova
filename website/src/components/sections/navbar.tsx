"use client";

import { useEffect, useState } from "react";
import { Menu, ShieldCheck, X } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { Logo } from "@/components/ui/logo";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-0 z-50">
      {/* Anti-fraud notice, as banks do. Collapses once the visitor scrolls. */}
      <div
        className={cn(
          "overflow-hidden bg-navy-900 text-white/85 transition-[height] duration-300",
          scrolled ? "h-0" : "h-9",
        )}
      >
        <p className="mx-auto flex h-9 max-w-6xl items-center justify-center gap-2 px-4 text-center text-xs">
          <ShieldCheck className="size-3.5 shrink-0 text-sky" />
          <span className="truncate">Sova will never ask for your PIN or OTP. Never share them.</span>
        </p>
      </div>

      <nav className="border-b border-navy-900/10 bg-white">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4">
          <a href="#top" aria-label="Sova home">
            <Logo variant="navy" />
          </a>

          <ul className="hidden items-center gap-8 md:flex">
            {site.nav.map((item) => (
              <li key={item.href}>
                <a href={item.href} className="text-sm font-medium text-slate-600 transition-colors hover:text-electric">
                  {item.label}
                </a>
              </li>
            ))}
          </ul>

          <div className="flex items-center gap-2">
            <a
              href="#waitlist"
              className="hidden rounded-xl bg-electric px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-electric-400 sm:inline-flex"
            >
              Join the waitlist
            </a>
            <button
              type="button"
              onClick={() => setOpen((v) => !v)}
              className="inline-flex size-10 items-center justify-center rounded-xl text-navy-900 hover:bg-navy-900/5 md:hidden"
              aria-label={open ? "Close menu" : "Open menu"}
              aria-expanded={open}
            >
              {open ? <X className="size-5" /> : <Menu className="size-5" />}
            </button>
          </div>
        </div>
      </nav>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="border-b border-navy-900/10 bg-white p-2 md:hidden"
          >
            {site.nav.map((item) => (
              <a
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                className="block rounded-xl px-4 py-3 text-base font-medium text-navy-800 hover:bg-mist"
              >
                {item.label}
              </a>
            ))}
            <a
              href="#waitlist"
              onClick={() => setOpen(false)}
              className="mt-1 block rounded-xl bg-electric px-4 py-3 text-center font-semibold text-white"
            >
              Join the waitlist
            </a>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  );
}
