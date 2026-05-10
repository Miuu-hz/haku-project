# Haku Crystal — Design System

> 箱 — a futuristic, glass-crystal redesign of **Haku**, the privacy-first AI personal assistant.

This design system extends the existing Haku Flutter app (a privacy-first, on-device AI life logger) into a more **futuristic, vivid, Apple-Glass-Crystal** visual language for a 3-screen redesign:

1. **Lookup** — a glanceable, Now-Brief-style overview screen that surfaces what's happening across the user's life: time, weather, calendar, recent thoughts, AI-suggested next actions.
2. **Chat** — a conversational thread between the user and the AI.
3. **Settings** — privacy, model, biometrics, theme.

---

## Sources

- **Codebase**: `Miuu-hz/haku-project` (Flutter / Dart). Browsed via GitHub. Key files referenced:
  - `lib/main.dart` — theme: `seedColor #6B4E71`, dark scaffold `#121212`, AppBar `#1A1A2E`, FAB `#9B7CB6`, `notoSansThaiTextTheme`
  - `lib/utils/constants.dart` — naming, Thai copy, app tagline
  - `lib/screens/main_navigation_screen.dart` — 3-tab structure (บันทึก / Haku AI / ตั้งค่า)
  - `AI_ROADMAP.md` — on-device Gemma 3 1B, Secret Chat architecture, RAG, Workers
  - `assets/images/app_icon.png` — wireframe cube + glowing turquoise spheres → core visual metaphor
- **Brand language**: Thai-first (UI strings ภาษาไทย), with English/Japanese accent (箱 = "hako/haku" = "box").
- **Design direction (user brief)**: futuristic, Apple-Glass-Crystal feel, vivid colors, lively in/out animations, Samsung Now Brief layout pattern for Lookup.

---

## Identity in one paragraph

Haku is a **glass box** that holds a private life. The visual identity literalizes this: a translucent navy crystal lattice with **vivid cyan-turquoise crystal cores** floating inside it, refracting light. Glassmorphism is the substrate — every surface is a frosted, slightly-tilted plane. Color erupts from inside the glass (gradients, glows) rather than sitting on top of it. The product is privacy-first, so the visual language is **calm, dim, intimate** — but never lifeless. Crystals pulse. Cards drift in. The AI breathes.

---

## Content Fundamentals

### Voice & tone
- **Bilingual, Thai-first**: UI strings are Thai; the AI replies in Thai (`hakuFacePrompt`). English appears in onboarding fragments, dev/settings, and category labels.
- **Friendly, gentle, warm-personal-assistant.** Not corporate.
- **Soft questions over imperatives.** From the codebase:
  - `'วันนี้เป็นยังไงบ้าง?\n\nเล่าให้ Haku ฟังหน่อย...'` ("How was your day? Tell Haku about it…") — note: **the AI refers to itself by name**, not "I".
  - `'วันนี้รู้สึกยังไง?'` ("How are you feeling today?")
- **You = คุณ (formal-friendly).** AI = Haku (third-person from itself).
- **Privacy is reassurance copy.** Examples from `constants.dart`:
  - "ข้อมูลของคุณเก็บบนเครื่องนี้เท่านั้น" — *Your data stays on this device only.*
  - "ทำงานได้แม้ไม่มีอินเทอร์เน็ต" — *Works without internet.*
  - "AI ประมวลผลบนเครื่อง ไม่ส่งข้อมูลขึ้น Cloud" — *AI runs on-device, nothing goes to the cloud.*
- **Mood scale uses real adjectives, not numbers.** `แย่มาก / แย่ / เฉยๆ / ดี / ดีมาก` — never "1 of 5".

### Casing & punctuation
- **Sentence case** for everything (Thai has no case but English copy follows). No ALL CAPS.
- **No periods on UI labels.** Periods only in body sentences.
- **Question marks survive translation** — interrogatives are central to the assistant voice.
- **Ellipses (`...`)** used to invite continuation: `เล่าให้ Haku ฟังหน่อย...`

### Emoji
- The codebase uses emoji **inside source-file comments** as section markers (🎌🎨🔒📍) — **not in user-facing UI strings**. Production strings stay clean. Our design system follows the same: emoji are tooling, not chrome. Use **Material Symbols** (rounded) for all UI iconography.

### Numbers & units
- Thai Buddhist year is **not** used in the codebase — it's `intl` standard formatting with `th` locale, so date strings render as Thai-month names with Gregorian years.
- Distances/times in the assistant context use natural language: "ใน 15 นาที", "ที่ตำแหน่งปัจจุบัน".

### Sample copy you can crib
- Empty state title: **"ยังไม่มีบันทึก"** / subtitle: **"กดปุ่ม "เขียน" เพื่อเริ่มบันทึกชีวิตของคุณ"**
- Save action: **"บันทึก"**, Settings: **"ตั้งค่า"**
- AI greeting (Lookup): **"สวัสดีตอนเช้า ☼"** *(no decorative emoji in production — use icon glyph instead)*

---

## Visual Foundations

### Color
- **Foundation is dark**, like the original Haku, but pivoted from desaturated dark-purple to **deep navy + crystal cyan**. The cube outline in the app icon is `#0A1F4D` and the glowing spheres are roughly `#3CDFFF`. We adopt those as primaries.
- **Primary**: `#3CDFFF` (Crystal Cyan) — the "glow inside the box". Used for AI affordance, focus, primary actions.
- **Secondary**: `#9B7CB6` (Lavender, retained from original Haku) — used for sentiment / mood / personal data.
- **Vivid accents**: lime `#A8FF60`, magenta `#FF6BD0`, gold `#FFD66B`, coral `#FF8C66` — used **sparingly, one per card category** to differentiate Now-Brief data types (calendar, mood, location, weather…).
- **Surfaces** are not flat — they are translucent navy with a soft outer glow and an inner edge highlight, on top of a deep-navy gradient field with subtle aurora.

### Type
- **Primary**: **Noto Sans Thai** + **Inter** (Latin pairing). Noto Sans Thai is what the codebase loads via `google_fonts: notoSansThaiTextTheme` and is essential for the bilingual UI. Inter is the closest sibling for Latin/numbers.
- **Display accents**: Inter Display (or Inter at 700+) for big numerical readouts (time, temperature) — tracked tight, slightly condensed feel.
- **Mono**: JetBrains Mono — for model paths, encryption status, dev surfaces in Settings.
- **Weights used**: 400 (body), 500 (UI labels), 600 (titles), 700 (display numerals).

### Spacing & radii
- **8-px base** scale: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 48 / 64.
- **Radii**: `10` (chip), `16` (input/button — matches Flutter `BorderRadius.circular(16)` from the codebase), `22` (card), `28` (sheet), `36` (hero / brief block), and `999` (pill).
- **Hairline** = 1px. **Glass edge** = 1px inner top highlight at 30% white + 1px outer bottom shadow at 60% black.

### Backgrounds
- Never flat. The app field is a **deep-navy radial gradient** (`#070B1A` → `#0E1638`) with two **soft aurora blooms** (cyan top-left, lavender bottom-right) at very low opacity, plus a **subtle film-grain noise** at ~3% to break banding.
- Cards float on this field with `backdrop-filter: blur(24px) saturate(140%)` over a translucent fill (`rgba(20, 30, 60, 0.55)`), creating the Apple-Glass effect.
- Hero/Now-Brief cards may carry a **caustic light streak** (a thin angled gradient sweep) to suggest refraction.

### Animation
- **Lively in/out** is core to the brief. We adopt three motion primitives:
  - **Crystal-rise** (entry): from `translateY(16px) scale(0.96) opacity(0)` to identity, ease `cubic-bezier(0.22, 1, 0.36, 1)`, 480ms — staggered 60ms per card.
  - **Caustic-shimmer** (idle): a 4s loop on hero glass — a 1.5°-tilted highlight slides from −10% to 110% at 8% opacity. Subtle.
  - **Tap-press**: scale to `0.97` over 120ms, then snap back over 220ms with overshoot (`cubic-bezier(0.34, 1.56, 0.64, 1)`).
- **Page transitions**: shared element morph for the AI orb (Lookup → Chat); Settings slides up as a sheet.
- **AI thinking**: the crystal core inside the cube logo *breathes* — opacity `0.6 ↔ 1.0` and scale `0.96 ↔ 1.04` on a 1.6s loop, plus a faint diffused glow.

### Hover / press / focus
- **Hover** (desktop preview): inner edge highlight goes from 30% → 50% white, outer glow widens by 4px. No color shift.
- **Press**: scale 0.97 + brief inner shadow pulse from cyan at 25% opacity.
- **Focus ring**: 2px Crystal Cyan outline at 4px offset, plus a 12px outer glow at 35% — **always visible** on keyboard nav.

### Borders, shadows, glow
- **Shadow system** (composite, dark-mode-correct):
  - `glass-1` = `0 1px 0 rgba(255,255,255,0.08) inset, 0 0 0 1px rgba(255,255,255,0.06), 0 12px 32px -8px rgba(0,0,0,0.55)`
  - `glass-2` = `glass-1` + `0 24px 64px -16px rgba(0,0,0,0.7)`
  - `glow-cyan` = `0 0 0 1px rgba(60,223,255,0.35), 0 0 24px rgba(60,223,255,0.45), 0 0 64px rgba(60,223,255,0.25)`
  - `glow-lavender` = same recipe in `#B68FFF`.
- **No** drop shadows under elements that should look glassy — use the inset highlight + outer color glow combo instead.

### Transparency & blur
- Use sparingly and **only on glass surfaces**. The default chrome uses 24px blur + 140% saturation. Tooltips/menus use 32px blur. Never blur the whole field — the aurora background reads through the glass and that's the magic.

### Imagery
- **Tone**: cool / nocturnal / refractive. Think a planetarium dome, not a sunset. Imagery (if used) should sit *behind* glass, not on top of it.
- **Photography**: rare. Reserve for onboarding splashes. Always cool-toned; never warm/grainy.
- **Avoid**: emoji decoration, rounded-corner+left-color-stripe cards, bluish-purple "AI gradient" tropes (we use cyan↔navy and lavender↔magenta, never the generic blue↔purple).

### Layout rules
- **Bottom nav** is always visible on the 3 main screens. It is itself a glass capsule with three icon destinations (matching the Flutter `NavigationBar` from `main_navigation_screen.dart`).
- **Status bar area** stays clear; we never push UI under it. Hero content begins ~48–60px below the safe area.
- **Cards on Lookup are heterogeneous** (different sizes/aspect ratios), arranged in a 2-column masonry — the Now-Brief inspiration. They are **not** a uniform grid.

### Cards
- Every card = glass surface + inner highlight + soft outer drop-shadow + an accent color sliver (a 2px gradient bar inside the top edge or a glowing dot in the corner — pick one per card type, never both).
- Corner radius: **22px** default, **28px** for hero blocks.
- Min internal padding: **20px** sides, **18px** vertical.

---

## Iconography

- **System**: **Material Symbols Rounded** (CDN). The Flutter codebase uses Material Icons (`Icons.book`, `Icons.chat_bubble`, `Icons.settings`, `Icons.book_outlined`, `Icons.chat_bubble_outline`, `Icons.settings_outlined`) — Material Symbols Rounded is the closest cross-platform web equivalent and renders both filled and outlined states from a single font via the `FILL` axis.
- **Stroke weight / style**: weight `400`, grade `0`, optical size `24` for inline; `weight 300` at large sizes for the cube/orb feel.
- **No emoji in UI strings** — mirrors the production codebase (where emoji live only in source comments).
- **No PNG icons** — all live; recolor via `color:` and `font-variation-settings`.
- **Brand cube/orb glyph** — we use the original `assets/haku-icon.png` (imported from the repo) for the app launch / about / signature spots. SVG redraws were avoided per the spec.

CDN URL: `https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,400,0,0`.

---

## Index

| File / folder | What it is |
|---|---|
| `colors_and_type.css` | All design tokens — colors, type scale, spacing, radii, shadows, motion easings |
| `fonts/` | Font loader CSS that pulls Noto Sans Thai + Inter + JetBrains Mono from Google Fonts |
| `assets/haku-icon.png` | App icon imported from the source repo — wireframe cube + crystal cores |
| `preview/` | Small card files registered as Design System tab cards (type, colors, spacing, components, brand) |
| `ui_kits/haku-app/` | High-fidelity recreation of the 3-screen mobile app: Lookup, Chat, Settings |
| `SKILL.md` | Agent skill manifest for using this system in Claude Code |

---

## Caveats

- **Fonts**: I am loading Noto Sans Thai, Inter, and JetBrains Mono from Google Fonts CDN — no `.ttf` files are bundled. If you want offline/embedded fonts, drop them into `fonts/` and I'll wire `@font-face` to local files.
- **No Figma was provided**, so visual decisions are made from code + the app icon. If you have Figma frames, please share — fidelity will jump.
- The **Lookup screen does not exist in the current Flutter codebase** (the current "Home" tab is a journal-entry list). I'm proposing this as the brief asked, drawing on Samsung Now Brief patterns rather than a pre-existing Haku design.
