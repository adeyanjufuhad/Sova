export const site = {
  name: "Sova",
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://sova.rumptycloud.app",
  description:
    "Sova keeps ajo, esusu and adashe savings circles honest: payments both sides confirm, a payout order drawn fairly, and a record every member can check. Sova never holds your money.",
  /** The live web app (the Flutter app built for the browser). */
  appUrl: process.env.NEXT_PUBLIC_APP_URL || "https://sova-app.rumptycloud.app",
  /** The Sova API; the waitlist form posts here. */
  apiUrl: process.env.NEXT_PUBLIC_API_URL || "https://sova-api.rumptycloud.app",
  // Set NEXT_PUBLIC_PLAY_STORE_URL once the app is live on Google Play. Until then
  // the download buttons send people to the waitlist instead of a raw APK.
  playStoreUrl: process.env.NEXT_PUBLIC_PLAY_STORE_URL || "",
  nav: [
    { label: "How it works", href: "#how" },
    { label: "Features", href: "#features" },
    { label: "Roadmap", href: "#roadmap" },
    { label: "Our promise", href: "#promise" },
    { label: "FAQ", href: "#faq" },
  ],
};
