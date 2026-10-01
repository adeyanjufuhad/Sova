import { Navbar } from "@/components/sections/navbar";
import { Hero } from "@/components/sections/hero";
import { Ticker } from "@/components/sections/ticker";
import { HowItWorks } from "@/components/sections/how-it-works";
import { RecordFlow } from "@/components/sections/record-flow";
import { Features } from "@/components/sections/features";
import { Circle } from "@/components/sections/circle";
import { Protection } from "@/components/sections/protection";
import { Collectors } from "@/components/sections/collectors";
import { Faq } from "@/components/sections/faq";
import { AppPreview } from "@/components/sections/app-preview";
import { SovaPromise } from "@/components/sections/promise";
import { Waitlist } from "@/components/sections/waitlist";
import { Footer } from "@/components/sections/footer";

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <HowItWorks />
        <RecordFlow />
        <Features />
        <Protection />
        <Circle />
        <Ticker />
        <Collectors />
        <SovaPromise />
        <AppPreview />
        <Faq />
        <Waitlist />
      </main>
      <Footer />
    </>
  );
}
