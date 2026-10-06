---
version: alpha
name: Sova
description: The design system of Sova, a record keeper for Nigerian ajo, esusu and adashe savings circles. Flat, white-first and blue, with navy ink, hairline borders and adire line patterns; it should feel as neat and trustworthy as a good bank statement, never like a crypto app. Sova never holds money, so nothing in the interface may look like a wallet or a balance held by Sova.

colors:
  navy-950: "#070F22"
  navy-900: "#0B1A33"
  navy-800: "#102447"
  navy-700: "#17305E"
  primary: "#1D4ED8"
  primary-hover: "#3B6AE8"
  on-primary: "#FFFFFF"
  sky: "#7DC3E3"
  sky-300: "#A9D8EE"
  canvas: "#FFFFFF"
  mist: "#F3F6FD"
  primary-tint: "#E8EDFB"
  ink: "#0B1A33"
  body: "#475569"
  mute: "#64748B"
  border: "rgba(11, 26, 51, 0.10)"
  border-strong: "rgba(11, 26, 51, 0.20)"
  error: "#0B1A33"

typography:
  display:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 34px
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: -0.8px
  h1:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 26px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: -0.5px
  h2:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 20px
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: -0.3px
  h3:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 16px
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
  body-sm:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1.3
  caption:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.35
  eyebrow:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 11px
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: 1.4px
    textTransform: uppercase
  money-lg:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 34px
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: -0.6px
    fontFeature: tnum
  money-sm:
    fontFamily: Plus Jakarta Sans, system-ui, sans-serif
    fontSize: 15px
    fontWeight: 600
    lineHeight: 1.3
    fontFeature: tnum
  mono:
    fontFamily: Geist Mono, ui-monospace, monospace
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.4

spacing:
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  xl2: 24px
  xl3: 32px
  xl4: 40px
  screen-h: 20px

rounded:
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  xl2: 24px
  full: 9999px

components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
    height: 54px
    typography: "{typography.label}"
  button-secondary:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    border: "1px solid {colors.border-strong}"
    rounded: "{rounded.md}"
    height: 54px
  card:
    backgroundColor: "{colors.canvas}"
    border: "1px solid {colors.border}"
    rounded: "{rounded.xl}"
    padding: "{spacing.lg}"
  adire-panel:
    backgroundColor: "{colors.primary}"
    pattern: "adire line motifs in white at 10-15% opacity"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
  notice-box:
    backgroundColor: "rgba(29, 78, 216, 0.10)"
    border: "1px solid rgba(29, 78, 216, 0.25)"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
---

## Overview

Sova keeps the record for rotating savings circles: who paid, who collected, in what order, and who stopped paying after collecting. Members pay each other by bank transfer or cash; **Sova never holds, moves, lends or invests money.** The interface has one job, which is to make that record feel as trustworthy as a bank statement while staying warm and Nigerian.

The system is **flat, white-first and blue**. A white canvas `{colors.canvas}` carries everything; royal blue `{colors.primary}` (`#1D4ED8`) is the only action colour; navy `{colors.navy-900}` (`#0B1A33`) is the ink. Depth comes from hairline borders and from switching between white and mist `{colors.mist}` surfaces, never from shadows, gradients or glass.

African identity comes from **adire line patterns**: indigo resist-dye motifs drawn as thin white lines over blue panels (`adire-panel`), as a strip above the website footer, and inside the brand card art. They are drawn in code (an SVG pattern on the website, a `CustomPainter` in the app), always at low opacity, never as photographs.

**Key characteristics**
- One accent: royal blue for every primary action. Sky `{colors.sky}` appears only on blue surfaces (eyebrows, small highlights).
- Navy, not black. Body copy is slate `{colors.body}`; captions `{colors.mute}`.
- Errors are navy or blue with an icon, never red: a missed payment is a fact on the record, not an alarm.
- Plus Jakarta Sans for everything, with tabular figures for naira. Geist Mono only for hashes, references and small labels on the website.
- Hairline borders (navy at 10% / 20%), radius 12 px on controls and 20 px on cards.
- Money always reads `₦120,000` (no kobo except on receipts: `₦120,000.00`). Phones read `0803 111 0001` and are stored as `+2348031110001`.

## Colors

### Brand and action
- **Royal blue** (`{colors.primary}`, `#1D4ED8`): every primary button, links, progress, focus rings, the adire panel background.
- **Royal blue hover** (`{colors.primary-hover}`, `#3B6AE8`): hover/pressed state of primary buttons on the website.
- **Sky** (`{colors.sky}`, `#7DC3E3`): the logo's light blue. Used for eyebrows and small marks on blue panels only.

### Ink and text
- **Navy 900** (`{colors.navy-900}`, `#0B1A33`): headings, primary text, the "Collecting" tag, error text.
- **Navy 950 / 800 / 700**: darker bands (the website's anti-fraud notice bar) and pressed states.
- **Body** (`#475569`) and **Mute** (`#64748B`): secondary and tertiary text.

### Surfaces and lines
- **Canvas** (`#FFFFFF`): the page and every card.
- **Mist** (`#F3F6FD`): alternate section bands on the website, chips, key chips on the draw screen.
- **Primary tint** (`#E8EDFB`, or royal blue at 10%): avatar backgrounds, notice boxes, selected states.
- **Border** (navy at 10%) and **border strong** (navy at 20%): every divider and outline.

### States
- Paid / confirmed: royal blue fill with a check.
- Awaiting: blue outline with a clock.
- Not paid: outlined, muted.
- Disputed / error: navy text, blue-tinted box, an icon that carries the meaning.

## Typography

**Plus Jakarta Sans** (bundled subset in the app with the ₦ sign and tabular figures; Google Fonts on the website) is the only text face. Hierarchy comes from weight (400 / 500 / 600 / 700 / 800) and colour, not from huge sizes: the app's largest text is 34 px. Headlines use slight negative tracking; eyebrows are 11 px, bold, upper-case with wide tracking and a small square marker.

Naira amounts always use **tabular figures** so columns of money line up. Hashes, seeds and references use tabular figures in the app and Geist Mono on the website.

Copy is in sentence case, active voice and plain words. No exclamation marks in confirmations, no "Oops", no "seamless" or "elevate". Ellipses are the single character `…`.

## Layout

- 4-point spacing grid (`{spacing.xs}` 4 px to `{spacing.xl4}` 40 px); 20 px side gutters on phones.
- The app is single-column and must fit a 320 px wide phone at 130% text size with no overflow (enforced by `app/test/layout_test.dart`).
- The website is contained to `max-w-6xl` (1152 px) and collapses to one column below 768 px. Full-height sections use `min-h-dvh`, never `100vh`.
- Buttons are full-width on phones and 54 px tall; touch targets are at least 44 px.

## Elevation and depth

There are **no drop shadows, glows, gradients or glass effects**. Elevation is expressed by:
1. a hairline border (`{colors.border}`),
2. a change of surface (white on mist, or white on royal blue),
3. a heavier border for the selected item (royal blue 1 px).

The only exceptions are the website hero's subtle blue light rays and the faint blueprint grid, both decorative, behind content, and stopped for people who prefer reduced motion.

## Shapes

- `{rounded.md}` 12 px: buttons, inputs, notice boxes.
- `{rounded.xl}` 20 px: cards and adire panels.
- `{rounded.full}`: status pills, avatars, small chips. Never on cards or primary buttons.

## Components

### Buttons
Primary: solid royal blue, white label, 12 px radius, 54 px tall, no shadow; pressed state scales to 0.97 with a light haptic in the app. Secondary: white with a navy 20% hairline. Text buttons for low-emphasis actions ("How it was drawn", "Raise a dispute").

### Cards
White, 1 px navy-10% border, 20 px radius, 16 px padding. Cards exist to group a record (a member row list, a payment, a rule set), not for decoration.

### Adire panel
The hero block at the top of a circle, the draw screen and a dispute: royal blue with adire lines at 10–15% white, an eyebrow in sky, a white headline and 85% white body text.

### Notice box
Inline information or error: blue tint background, blue 25% border, navy text, a leading icon. Used for "You are part of this dispute…", errors, and empty states.

### Money moments
- **PIN sheet:** every money action (pay, confirm, payout, vote, settle) asks for the 4-digit PIN in a bottom sheet.
- **Receipt:** bank-style, with Sova reference `SV-XXXX`, both sides' confirmation times and amounts with kobo.
- **Fair draw:** members start A to Z, their keys settle one by one, then the cards slide into turn order; the phone then rechecks the seed and the order.
- **Dispute vote:** two outlined choices ("It arrived" / "It didn't arrive"), a tally bar per side and the number of votes needed.

### Section heading (website)
Split by default: eyebrow and a heavy headline (800, tight tracking, up to 60 px) on the left, the supporting sentence on the right, bottom-aligned; it stacks on phones. Centred only for narrow or radial sections (FAQ, the orbit of names). Headlines in half-width columns stop at 48 px.

### Payout calculator (website)
The signature interactive card: contribution, members and frequency in a white card with a hairline border, and the result in an adire panel below it: what you collect (contribution × (members − 1)), how long the cycle lasts, and that you pay in exactly what you collect. Arithmetic only, never projections.

### Record band (website)
A full-width navy band that shows the product as the visual: a mockup of the circle record (entry kinds and the hash rule, hashes labelled as examples) with a white "rechecked in your browser" card overlapping its corner. Depth comes from the overlap, not a shadow. One white button per band.

### Ghost watermark (website)
Oversized words (800 weight, navy at 3–4% opacity) behind a section to set its theme, such as "ajo esusu adashe" behind the orbit of names, with the orbit drawn as thin sky-blue rings. Decorative and hidden from screen readers.

### Footer (website)
Navy, opening with a large conversational headline and one white button, then the links, the safety note and the "not a bank, lender or wallet" disclosure.

### Empty state (app)
A white card with a 64 px adire tile holding a white icon, a short title, one sentence on what to do, and up to two full-width actions. Used when a whole list is empty (circles, activity, disputes) and for the "page not found" screen.

### Motion
Short and purposeful: staggered entrances (60–80 ms apart), count-up for the next payout, 200–300 ms transitions on transform and opacity only. Buttons press to 0.98 scale; cards lift 2 px on hover. Every animation is skipped when the system asks for reduced motion.

## Do's and Don'ts

### Do
- Use royal blue for the one primary action on each screen.
- Show money with tabular figures and the `₦` sign.
- Say plainly what is built; label anything unbuilt "coming soon" or "roadmap".
- Call the ledger "tamper-evident", never "tamper-proof".
- Keep adire patterns thin, low-opacity and behind content.

### Don't
- Don't use gradients, neon, glows, glass, or large drop shadows.
- Don't use red for errors or missed payments.
- Don't show anything that looks like a wallet, balance or money held by Sova.
- Don't swap Plus Jakarta Sans for another face, or use emojis in the interface.
- Don't invent statistics, testimonials or partners.
