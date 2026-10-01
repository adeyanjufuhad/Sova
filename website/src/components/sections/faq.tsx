"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { SectionHeading } from "@/components/ui/section-heading";
import { cn } from "@/lib/utils";

type QA = { q: string; a: string };

// Pidgin copy should be reviewed by a native speaker before launch.
const faqs: Record<"en" | "pcm", QA[]> = {
  en: [
    {
      q: "Does Sova hold my money?",
      a: "No. Contributions go straight from member to member, by transfer or cash, the way your group already does it. Sova keeps the record of who paid, when, and whose turn is next.",
    },
    {
      q: "What if someone collects their payout and stops paying?",
      a: "Sova can't force anyone to pay, but it makes it much harder to get away with. New members collect last and join on another member's word, everyone signs the group's rules, and anyone who collects and then misses a payment is flagged on the group record.",
    },
    {
      q: "Do I need a smartphone to join a circle?",
      a: "No. Members without smartphones get SMS reminders and receipts, and their collector or group admin can record payments for them.",
    },
    {
      q: "How much does it cost?",
      a: "Joining the waitlist is free, and members will use Sova for free. We'll share pricing for collectors who run many groups before we launch.",
    },
    {
      q: "When can I download the app?",
      a: "Android comes first, on Google Play. Join the waitlist to hear the moment it's ready, or to become one of our early testers.",
    },
    {
      q: "Is my information safe?",
      a: "We only use your information to run your savings circle, and we don't sell it. Sova is being built to follow Nigeria's Data Protection Act.",
    },
  ],
  pcm: [
    {
      q: "Sova dey hold my money?",
      a: "No o. Una money dey go straight from member to member, by transfer or cash, as una don dey do before. Sova just dey keep record of who pay, when e pay, and whose turn be next.",
    },
    {
      q: "If person collect money finish, come stop to pay nko?",
      a: "Sova no fit force anybody pay, but e go hard person to do am. New member go collect last and somebody for the group go stand for am, everybody go sign the group rules, and anybody wey collect finish come stop to pay go show for the group record.",
    },
    {
      q: "I need smartphone before I fit join?",
      a: "No. If you no get smartphone, you go dey receive SMS reminder and receipt, and your collector or group admin fit record your payment for you.",
    },
    {
      q: "How much e cost?",
      a: "To join the waitlist na free, and members go use Sova free. We go talk the price for collectors wey dey run plenty groups before we launch.",
    },
    {
      q: "When app go ready?",
      a: "Android go come first, for Google Play. Join the waitlist make we tell you as e ready, or make you test am before everybody.",
    },
    {
      q: "My information dey safe?",
      a: "We dey use your information only to run your ajo, we no dey sell am. We dey build Sova to follow Nigeria Data Protection Act.",
    },
  ],
};

export function Faq() {
  const [lang, setLang] = useState<"en" | "pcm">("en");
  const [open, setOpen] = useState<number | null>(0);

  return (
    <section id="faq" className="relative mx-auto max-w-3xl scroll-mt-24 px-4 py-24 sm:py-32">
      <SectionHeading eyebrow="FAQ" title="Questions people ask us" />

      <div className="mt-10 flex justify-center">
        <div role="tablist" aria-label="Language" className="inline-flex rounded-full border border-navy-900/10 bg-mist p-1">
          {(
            [
              ["en", "English"],
              ["pcm", "Pidgin"],
            ] as const
          ).map(([key, label]) => (
            <button
              key={key}
              role="tab"
              aria-selected={lang === key}
              onClick={() => setLang(key)}
              className={cn(
                "rounded-full px-5 py-2 text-sm transition",
                lang === key ? "bg-electric text-white shadow-sm" : "text-slate-600 hover:text-navy-900",
              )}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <ul className="mt-10 space-y-3">
        {faqs[lang].map((item, i) => {
          const isOpen = open === i;
          return (
            <li key={item.q} className="overflow-hidden rounded-2xl border border-navy-900/10 bg-white transition-colors hover:border-electric/25">
              <button
                onClick={() => setOpen(isOpen ? null : i)}
                aria-expanded={isOpen}
                className="flex w-full items-center justify-between gap-4 px-5 py-5 text-left sm:px-6"
              >
                <span className="font-medium text-navy-900">{item.q}</span>
                <Plus
                  className={cn("size-5 shrink-0 text-electric transition-transform duration-300", isOpen && "rotate-45")}
                />
              </button>
              <div
                className={cn(
                  "grid transition-[grid-template-rows] duration-300",
                  isOpen ? "grid-rows-[1fr]" : "grid-rows-[0fr]",
                )}
              >
                <div className="overflow-hidden">
                  <p className="px-5 pb-5 text-slate-600 sm:px-6">{item.a}</p>
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
