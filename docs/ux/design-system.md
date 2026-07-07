# SoloPM Design System

Status: living document. Tokens live in `Sources/SoloPMApp/Views/SoloPMDesignSystem.swift`; this page explains when to use them. New UI should consume tokens instead of hardcoding values, and should read like the surrounding native macOS surface — SoloPM's visual voice is "calm, native, glanceable".

## Principles

1. **Native first.** Use system semantic colors, SF Symbols, and standard controls. Custom chrome must earn its place; dark mode and accessibility come free only when we stay semantic.
2. **Hierarchy over decoration.** Every surface has one primary action. Prominence (`.borderedProminent`, size, position) marks it; everything else stays quiet.
3. **Glanceable status.** Status is communicated by tone color + shape (chip), never by color alone in prose. The same meaning must render the same tone everywhere.
4. **Calm by default.** Neutral grays for structure, tint only for interactive/primary elements, orange/red reserved for attention/danger. No decorative gradients.

## Tokens

### Spacing (`SoloPMSpacing`)

| Token | Value | Use |
| --- | ---: | --- |
| `xs` | 4 | Icon-to-label gaps, chip padding |
| `sm` | 8 | Related controls in a row, list row spacing |
| `md` | 12 | Card interior padding, section internals |
| `lg` | 16 | Panel edge padding, between sections |
| `xl` | 24 | Large surface padding (sheets, onboarding) |

### Corner radius (`SoloPMRadius`)

| Token | Value | Use |
| --- | ---: | --- |
| `control` | 6 | Small interactive elements |
| `card` | 10 | Grouped content cards, pills |

Always pair with `style: .continuous`.

### Status tones (`SoloPMTone`)

| Tone | Color | Meaning |
| --- | --- | --- |
| `neutral` | secondary | Informational counts and labels |
| `attention` | orange | Needs the user soon (overdue counts, recoverable errors) |
| `danger` | red | Destructive or blocking states |
| `positive` | green | Confirmed healthy/ready states |

Route every status color through `SoloPMTone` — do not use raw `.orange`/`.red` in new views.

## Components

- **`SoloPMStatusChip`** — capsule count/status badge. Use for glanceable values (menu bar summary, board counts). Neutral values render quiet; attention values render tinted.
- **`.soloCard()`** — inset grouped-content treatment for panels (quaternary fill, `card` radius). Use to group related read-only information; do not nest cards.

## Patterns

- **Primary action**: exactly one `.borderedProminent` button per surface (e.g. onboarding Continue, quick-add submit). Secondary actions stay `.bordered` or `.borderless`.
- **Empty states**: `ContentUnavailableView` with a one-line description that names the next action the user can take.
- **Errors**: inline `Label` with `exclamationmark.triangle`, `attention` tone, max 2 lines with `fixedSize(horizontal: false, vertical: true)`. No modal alerts for recoverable errors.
- **Icon feature marks** (onboarding, feature intros): SF Symbol at 34pt medium in a 76pt circle filled with `.tint.opacity(0.12)`.
- **Step indicators**: capsule dots (active dot elongated + tinted), with a localized "Step N of M" accessibility label.

## Writing

- User-facing text never uses internal jargon (smoke, harness, watcher, receipt digests). Status text describes what the user can do next, not internal state names.
- Sentence case for labels and descriptions; title case only for window titles and plan names.
- Every static literal in `Text`/`Label`/`Button`/help/accessibility modifiers must have entries in both `en.lproj` and `ja.lproj` (enforced by `AppExperienceSourceTests`).

## Accessibility floor (per component)

- Identifier following `docs/quality/accessibility-identifiers.md` (`screen-area-action`).
- Label or visible text meaningful in VoiceOver; hint whenever the action writes data.
- Semantic fonts only (`.caption`…`.title2`) so Dynamic Type scales.
