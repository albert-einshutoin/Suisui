# Suisui Design System — Calm Signal Desk

Status: living document. Tokens live in `Sources/SuisuiApp/Views/SuisuiDesignSystem.swift`; this page explains when to use them. New UI should consume tokens instead of hardcoding values.

Calm Signal Desk is Suisui's visual direction: quiet enough for everyday project work, distinctive when the product has something useful to say, and familiar enough that a first-time macOS user can operate it without learning a custom interface language.

## Principles

1. **Native first.** Use system semantic colors, SF Symbols, and standard controls. Keep the native sidebar, toolbar, `Form`, and inspector roots unskinned so macOS continues to own selection, vibrancy, focus, and window behavior.
2. **Hierarchy over decoration.** Every surface has one primary action. Prominence (`.borderedProminent`, size, position) marks it; everything else stays quiet.
3. **Glanceable status.** Status is communicated by tone color + shape (chip), never by color alone in prose. The same meaning must render the same tone everywhere.
4. **Calm by default.** Neutral semantic surfaces provide structure. Solo Blue marks selection and primary actions; Signal Amber identifies assistant guidance or attention. No glass, decorative gradients, or ornamental animation.
5. **Accessible by construction.** Semantic fonts, adaptive colors, standard control sizing, and Reduce Motion behavior are token-level requirements rather than per-screen polish.

## Tokens

### Brand (`SuisuiBrand`)

| Token | Meaning | Use |
| --- | --- | --- |
| `soloBlue` | Product identity and confident action | Tint, selected borders, active states |
| `signalAmber` | Warm signal without alarm | Assistant guidance and attention states |

Both colors are adaptive. Do not copy their RGB values into views.

### Typography (`SuisuiTypography`)

| Token | Use |
| --- | --- |
| `sectionTitle` | Group heading inside a page |
| `body` | Normal explanatory or task content |
| `metadata` | Supporting timestamps and secondary facts |
| `compactLabel` | Dense chips and compact utility labels |

The type ramp uses semantic SwiftUI fonts so user scaling and system legibility remain available.

### Surfaces and borders

`SuisuiSurface` provides solid, adaptive fills:

- `canvas`: owned content canvases only, never a native container root.
- `groupedContent`: related content inside `.soloCard()`.
- `elevatedSelection`: selected custom content where native selection is unavailable.
- `assistantSignal`: AI suggestions and assistant guidance.

`SuisuiBorder` provides `subtle`, `selected`, `attention`, and `danger` edges. Borders support hierarchy; they do not replace text, icons, or accessible labels.

### Motion (`SuisuiMotion`)

`quick`, `standard`, and `emphasis` are duration choices for state changes that benefit from spatial continuity. Call `SuisuiMotion.animation(duration:reduceMotion:)` with `@Environment(\.accessibilityReduceMotion)`. Under Reduce Motion the animation returns `nil`; do not substitute a faster decorative animation.

Icon sizing and control density use SwiftUI's semantic font and native
`ControlSize` APIs directly. Add a shared token only after multiple live views
need the same non-native value.

### Spacing (`SuisuiSpacing`)

| Token | Value | Use |
| --- | ---: | --- |
| `xs` | 4 | Icon-to-label gaps, chip padding |
| `sm` | 8 | Related controls in a row, list row spacing |
| `md` | 12 | Card interior padding, section internals |
| `lg` | 16 | Panel edge padding, between sections |

### Corner radius (`SuisuiRadius`)

| Token | Value | Use |
| --- | ---: | --- |
| `control` | 6 | Small interactive elements |
| `card` | 10 | Grouped content cards, pills |

Always pair with `style: .continuous`.

### Status tones (`SuisuiTone`)

| Tone | Color | Meaning |
| --- | --- | --- |
| `neutral` | secondary | Informational counts and labels |
| `attention` | orange | Needs the user soon (overdue counts, recoverable errors) |
| `danger` | red | Destructive or blocking states |
| `positive` | green | Confirmed healthy/ready states |

Route every status color through `SuisuiTone`. A raw status color is not allowed in new views: status must also include text, an icon, or shape so meaning never depends on color alone.

## Components

- **`SuisuiStatusChip`** — capsule count/status badge. Use for glanceable values (menu bar summary, board counts). Neutral values render quiet; attention values render tinted.
- **`.soloCard()`** — solid adaptive grouped-content treatment for panels. Use to group related information; do not nest cards.
- **`.soloAssistantSignal()`** — restrained Signal Amber treatment for AI suggestions or assistant guidance. It is not a general warning card and must not replace native alerts.

## Patterns

- **Primary action**: exactly one `.borderedProminent` button per surface (e.g. onboarding Continue, quick-add submit). Secondary actions stay `.bordered` or `.borderless`.
- **Empty states**: `ContentUnavailableView` with a one-line description that names the next action the user can take.
- **Errors**: inline `Label` with `exclamationmark.triangle`, `attention` tone, max 2 lines with `fixedSize(horizontal: false, vertical: true)`. No modal alerts for recoverable errors.
- **Icon feature marks** (onboarding, feature intros): use a semantic SwiftUI font with a tinted container.
- **Step indicators**: capsule dots (active dot elongated + tinted), with a localized "Step N of M" accessibility label.

## Writing

- User-facing text never uses internal jargon (smoke, harness, watcher, receipt digests). Status text describes what the user can do next, not internal state names.
- Sentence case for labels and descriptions; title case only for window titles and plan names.
- Every static literal in `Text`/`Label`/`Button`/help/accessibility modifiers must have entries in both `en.lproj` and `ja.lproj` (enforced by `AppExperienceSourceTests`).

## Accessibility floor (per component)

- Identifier following `docs/quality/accessibility-identifiers.md` (`screen-area-action`).
- Label or visible text meaningful in VoiceOver; hint whenever the action writes data.
- Semantic fonts only (`.caption`…`.title2`) so Dynamic Type scales.
- Decorative motion is disabled when Reduce Motion is active.
