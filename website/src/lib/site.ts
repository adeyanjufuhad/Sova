export const site = {
  name: "Sova",
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://sova.vercel.app",
  description:
    "Sova digitises ajo, esusu and adashe savings circles for Nigerian traders and collectors: reminders, SMS receipts and a clear record of every contribution. Sova never holds your money.",
  // Set NEXT_PUBLIC_PLAY_STORE_URL once the app is live on Google Play. Until then
  // the download buttons send people to the waitlist instead of a raw APK.
  playStoreUrl: process.env.NEXT_PUBLIC_PLAY_STORE_URL || "",
  nav: [
    { label: "How it works", href: "#how" },
    { label: "Features", href: "#features" },
    { label: "Collectors", href: "#collectors" },
    { label: "Our promise", href: "#promise" },
    { label: "FAQ", href: "#faq" },
  ],
};
