# SwiftPM Target Split Evaluation

Date: 2026-07-03

## Decision

Decision: defer new SwiftPM targets.

Suisui should not add Work Management, Automation Core, Integration Core, or
App Shell targets in the current refactor pass. The boundaries are now
documented and source-level tests are active, but the measured coupling still
shows that a package graph change would be mostly structural churn rather than
a clear build, security, or contributor ergonomics win.

No target split happens only for style. A target split is allowed only after
import-boundary tests land first and the candidate domain can be moved without
weakening release evidence, runtime smoke, accessibility, localization,
security, or approval-before-execution contracts.

## Current Package Graph

`Package.swift` currently defines seven targets:

| Target | Depends on | Current role |
| --- | --- | --- |
| `SuisuiCore` | system `sqlite3` linker setting | Domain models, stores, ports, security, audit, developer-mode automation, and reusable runtime contracts. |
| `SuisuiExternalConnectors` | `SuisuiCore` | Optional SaaS connector implementations and connector-specific OAuth lifecycle. |
| `SuisuiGoogleCalendarRuntime` | `SuisuiCore` | Google Calendar runtime OAuth, HTTP clients, calendar list, and sync adapters. |
| `SuisuiiOS` | `SuisuiCore` | iOS companion surface. |
| `SuisuiWeb` | `SuisuiCore` | Web MVP surface. |
| `Suisui` | `SuisuiCore`, `SuisuiGoogleCalendarRuntime`, `Sparkle`, `SwiftTerm` | macOS executable, app shell, SwiftUI views, composition roots, and platform adapters. |
| `SuisuiCLI` | `SuisuiCore` | CLI read-only/reporting surface. |

The app target still deliberately avoids `SuisuiExternalConnectors`. Optional
connector code remains available to tests and future integrations without
broadening the shipping app dependency graph.

## Measurements

Measured from the repository on 2026-07-03:

| Measurement | Result | Implication |
| --- | --- | --- |
| Source file count by target | `SuisuiCore` 122, `SuisuiApp` 33, `SuisuiExternalConnectors` 1, `SuisuiGoogleCalendarRuntime` 1, `SuisuiCLI` 1, `SuisuiiOS` 1, `SuisuiWeb` 1 | Core is still the dominant dependency closure; target splits would mostly move Core-internal coupling unless more domain files are isolated first. |
| Core folder concentration | `Sources/SuisuiCore/App` 38 files / 24,090 LOC, `WorkManagement` 3 files / 1,304 LOC, `ExternalMCP` 8, `Voice` 12, `DeveloperMode` 12, `Database` 2, `Security` 5, `Review` 3 | Some domains have folders, but Work Management and planning still share the broad App layer. |
| Import distribution | `Foundation` 148, `SuisuiCore` 33, `SwiftUI` 21, `CryptoKit` 11, `UniformTypeIdentifiers` 10, `Combine` 9, `AppKit` 4, `SuisuiGoogleCalendarRuntime` 2 | UI/platform imports are concentrated in the app target, while most domain code shares Foundation/Core. |
| Platform import placement | SwiftUI/AppKit/Sparkle/SwiftTerm/AuthenticationServices/EventKit imports are in `Sources/SuisuiApp` only. | Existing boundary tests are already enforcing the most valuable split: platform code stays outside Core/runtime targets. |
| Local verification cost | `./scripts/ci.sh` completed locally in about 20 seconds during the preceding integration refactor. | Current build/test cost does not justify package graph churn by itself. |

## Candidate Target Assessment

| Candidate target | Potential benefit | Current blocker | Decision |
| --- | --- | --- | --- |
| Work Management | Smaller domain API for projects, tasks, inbox, milestones, due work, and board snapshots. | `Sources/SuisuiCore/App` still holds broad board, schedule, sync, and presentation view-model code. Splitting now would require either cyclic dependencies or a large behavior-preserving move in the same PR. | Defer until Work Management owns a stable closure of value types, stores, services, and view-model boundaries. |
| Automation Core | Clear approval-before-execution package for assistant queue, review sessions, receipts, cost preview, and audit transitions. | Automation still crosses Work Management mutations, audit/security redaction, developer workflow tools, and runtime receipts. Boundary tests currently give better protection with less graph churn. | Defer until queue translation, execution coordination, and receipt persistence are independently importable. |
| Integration Core | Reusable connector contracts for Google Calendar, MCP, notifications, SaaS connectors, and shared HTTP/value contracts. | `SuisuiGoogleCalendarRuntime` and `SuisuiExternalConnectors` already separate concrete runtime adapters. The shared value/protocol contracts now live in Core without linking optional connector implementations into the app. | Defer; continue extracting only shared value/protocol contracts when they reduce coupling. |
| App Shell | Smaller app composition surface for launch, scene wiring, settings runtime, and platform permissions. | The executable target already is the app shell. Further target splitting would not help OSS contributors unless composition factories can be reused independently from SwiftUI views and platform adapters. | Defer; keep folder-level `Composition`, `Views`, and `Adapters` boundaries. |

## Measurement Commands

Refresh the measurements before reopening the decision:

```sh
for d in Sources/SuisuiCore Sources/SuisuiApp Sources/SuisuiExternalConnectors Sources/SuisuiGoogleCalendarRuntime Sources/SuisuiCLI Sources/SuisuiiOS Sources/SuisuiWeb; do
  printf "%s " "$d"
  find "$d" -name '*.swift' -type f | wc -l
done

for d in Sources/SuisuiCore/App Sources/SuisuiCore/WorkManagement Sources/SuisuiCore/ExternalMCP Sources/SuisuiCore/Voice Sources/SuisuiCore/DeveloperMode Sources/SuisuiCore/Database Sources/SuisuiCore/Security Sources/SuisuiCore/Review Sources/SuisuiApp/Composition Sources/SuisuiApp/Views Sources/SuisuiApp/Adapters; do
  printf "%s " "$d"
  find "$d" -name '*.swift' -type f 2>/dev/null | wc -l
done

rg '^import ' Sources -g '*.swift' | sed 's/:import / /' | awk '{print $2}' | sort | uniq -c | sort -nr | head -30
```

## Gates Before Any Target Split

Any future PR that changes `Package.swift` for these candidate domains must land
the import-boundary tests before the package graph change and must document the
candidate dependency closure.

Required gates:

- `swift test --filter ArchitectureBoundaryTests`
- `swift test --filter AppExperienceSourceTests`
- Domain-specific focused tests for moved code
- `./script/check_security_regressions.sh`
- `git diff --check`
- Release evidence contracts remain current
- Runtime smoke remains green for the touched runtime path
- Accessibility identifiers and VoiceOver/manual gates remain stable
- Optional connector targets do not become app dependencies unless the PR
  explicitly documents the product reason and adds a boundary test
- Candidate import-closure tests prove the extracted domain does not depend on
  SwiftUI, app runtime adapters, optional connector implementations, or sibling
  domains that would introduce cycles.

## Revisit Triggers

Reconsider target splits when at least one of these becomes true:

- A domain has a stable source folder with a one-way dependency closure and no
  direct platform imports.
- Build/test time or contributor setup cost is measurably improved by compiling
  a smaller target.
- OSS contributors need a reusable package boundary, not just a cleaner folder
  layout.
- Boundary tests can fail before the package graph is changed.
- Security, release, runtime, and accessibility gates can be run against the
  extracted target without weaker coverage.
