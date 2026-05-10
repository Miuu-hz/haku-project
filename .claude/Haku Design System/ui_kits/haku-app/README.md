# Haku App — UI Kit

A high-fidelity, click-through recreation of the **Haku Crystal** mobile app: 3 screens, glass-morphic, on-device AI assistant.

## Files
- `index.html` — entry point. Renders inside an iOS frame with all 3 screens stitched together via tab state.
- `styles.css` — kit-local CSS (cards, nav, composer, settings rows, etc) — pulls tokens from `../../colors_and_type.css`.
- `Lookup.jsx` — Now-Brief style lookup screen with masonry of contextual cards (Suggestion, Calendar, Weather, Mood, Location, Health, Journal).
- `Chat.jsx` — Conversational thread with thinking-state animation, event-confirmation card embed, glass composer.
- `Settings.jsx` — Profile + grouped settings (Privacy, AI, Appearance, Data) with toggles, status pills, accent picker.
- `ios-frame.jsx` — Standard iPhone bezel (starter component).

## Components covered
- `<BottomNav>` — glass capsule, 3 tabs, animated selected pill.
- `<CrystalCore>` — the breathing AI orb (sm / default / lg).
- `<Bubble>` — chat bubble (`from="ai" | "me"`).
- `<Toggle>` — switch with crystal glow when on.
- `<PillStat>` / `<HakuChip>` — micro tags.
- Glass card primitives (`.gcard`, `.gcard.hero`, accent slivers, vivid color modifiers).

## Caveats
- The 3-tab structure mirrors `lib/screens/main_navigation_screen.dart`. Lookup is **net-new** (the brief asks for a Now-Brief surface that the codebase doesn't have yet).
- All copy is Thai-first per the production codebase. Latin appears only in eyebrow / dev strings.
- AI responses are pre-scripted; no LLM is wired up.
