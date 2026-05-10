---
name: haku-design
description: Use this skill to generate well-branded interfaces and assets for Haku (箱), a privacy-first on-device AI personal assistant, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping in the Haku Crystal visual language (glass-morphic, vivid cyan-on-navy, lively crystal motion).
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

## Quick reference
- Tokens: `colors_and_type.css` (CSS vars for color, type, spacing, radii, shadows, motion).
- Brand: cyan crystal core (`#3CDFFF`) + navy (`#0A1F4D`) + retained Haku lavender (`#9B7CB6`) + 5 vivid accents (lime / mint / gold / coral / magenta) for category cards.
- Type: Noto Sans Thai + Inter + JetBrains Mono (Google Fonts CDN).
- Icons: Material Symbols Rounded (CDN).
- Motion: glass-rise entry, 1.6s breath on AI orb, 4s caustic shimmer on glass.
- UI kit: `ui_kits/haku-app/` — 3 screens (Lookup / Chat / Settings) inside an iOS frame.
