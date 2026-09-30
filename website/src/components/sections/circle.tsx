"use client";

import {
  BadgeCheck,
  Bell,
  CloudOff,
  ListOrdered,
  MessageSquareText,
  Mic,
  Store,
  UsersRound,
} from "lucide-react";
import { OrbitingCircles, type Orbit } from "@/components/ui/orbiting-circles";
import { SectionHeading } from "@/components/ui/section-heading";

const orbits: Orbit[] = [
  {
    size: "size-110 md:size-180",
    duration: 36,
    icons: [
      { icon: Bell, label: "Reminders", angle: -60 },
      { icon: MessageSquareText, label: "SMS receipts", angle: 60 },
      { icon: UsersRound, label: "Members", angle: 180 },
    ],
  },
  {
    size: "size-150 md:size-220",
    duration: 48,
    icons: [
      { icon: ListOrdered, label: "Payout order", angle: -90 },
      { icon: Mic, label: "Voice prompts", angle: 0 },
      { icon: BadgeCheck, label: "Verified collectors", angle: 90 },
      { icon: CloudOff, label: "Works offline", angle: 180 },
    ],
  },
  {
    size: "size-180 md:size-265",
    duration: 60,
    icons: [
      { icon: Store, label: "Market traders", angle: -45 },
      { icon: UsersRound, label: "Savings circles", angle: 45 },
    ],
  },
];

export function Circle() {
  return (
    <section className="overflow-hidden pt-24 sm:pt-32">
      <SectionHeading
        className="px-4"
        eyebrow="One circle"
        title="Everything your ajo needs, in one place."
        sub="Members, collectors, reminders and receipts, all turning around the same shared record."
      />
      <div className="mt-6">
        <OrbitingCircles orbits={orbits} />
      </div>
    </section>
  );
}
