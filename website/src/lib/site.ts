export const site = {
  name: "Sova",
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://sova.rumptycloud.app",
  description:
    "Sova keeps ajo, esusu and adashe savings circles honest: payments both sides confirm, a payout order drawn fairly, and a record every member can check. Sova never holds your money.",
  /** The live web app (the Flutter app built for the browser). */
  appUrl: process.env.NEXT_PUBLIC_APP_URL || "https://sova-app.rumptycloud.app",
  /** The Sova API; the waitlist form posts here. */
  apiUrl: process.env.NEXT_PUBLIC_API_URL || "https://sova-api.rumptycloud.app",
  /** Chain heads published outside Sova's database by .github/workflows/ledger-anchors.yml. */
  anchorsUrl:
    process.env.NEXT_PUBLIC_ANCHORS_URL ||
    "https://raw.githubusercontent.com/adeyanjufuhad/Sova/ledger-anchors/anchors.json",
  /** Where anyone can see when each anchor was published (the branch's git history). */
  anchorsHistoryUrl: "https://github.com/adeyanjufuhad/Sova/commits/ledger-anchors/anchors.json",
  // Set NEXT_PUBLIC_PLAY_STORE_URL once the app is live on Google Play. Until then
  // the download buttons send people to the waitlist instead of a raw APK.
  playStoreUrl: process.env.NEXT_PUBLIC_PLAY_STORE_URL || "",
  // The owner's inbox for privacy and terms questions (shown on /privacy and /terms).
  contactEmail: process.env.NEXT_PUBLIC_CONTACT_EMAIL || "adeyanjufuhad@gmail.com",
  nav: [
    { label: "How it works", href: "#how" },
    { label: "Features", href: "#features" },
    { label: "Roadmap", href: "#roadmap" },
    { label: "Verify a circle", href: "/verify/" },
    { label: "FAQ", href: "#faq" },
  ],
};
