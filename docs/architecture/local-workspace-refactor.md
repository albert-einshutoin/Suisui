# Local workspace architecture

## Goal and acceptance

Organize the complete local workspace flow in one PR: capture, task/project
commands, Inbox triage, Today/read models, local schedule drafts, search,
navigation, review handoff, and execution evidence. Preserve stored data,
approval binding, localization, accessibility identifiers, and platform ports.

- The board presentation facade has feature-owned implementation files; local
  commands and pure calculations do not acquire provider/OS dependencies.
- Inbox creation has one atomic persistence path for plain and enriched input.
- One parsed capture draft supplies both the visible date preview and saved
  values; title edits preserve explicit date edits/removal, and removing an
  inferred date preserves the original text.
- Search distinguishes loading, no matches, and failure, rejects stale results,
  and gives knowledge results a read-only destination.
- Board reloads do not repeat the originating window's successful refresh;
  a failed post-write reload and other windows still receive changes. Missed
  work follow-up remains evaluated for every notification.
- Existing approval/execution and recovery contracts remain intact.
- Focused tests, security checks, specialist/Stop review, complete local CI,
  current-source UI evidence, and hosted PR checks pass before merging to main.

## Dependency direction

SwiftUI views -> feature presentation/actions -> local commands/read models ->
store ports -> SQLite/filesystem adapters. Approval and external execution
remain separate feature owners. Composition alone selects concrete runtimes.
No server, new dependency, or persistent schema migration is needed.

## Implementation and validation order

1. Reproduce search error masking and non-atomic enriched Inbox creation with
   in-memory SQLite tests; run existing boundary checks.
2. Extract feature owners and consolidate capture persistence. Reuse the board
   facade for existing macOS/CLI consumers while removing old implementations.
3. Move asynchronous search state out of the SwiftUI view, add read-only preview,
   show parsed capture dates, and make change notifications origin-aware.
4. Run targeted behavior and source checks; fix regressions and self-review.
5. Obtain one specialist review and the Companion Stop Review Gate; resolve
   in-scope findings together, then review the affected paths.
6. Run `./ci/run-all.sh` (full non-UI, runtime, visual, performance), record real
   results, create the PR, verify hosted checks for its head, and merge it.

## Evidence

- Base: `d2a4cf4ef81607eae2b8d9580f995434fe48e2a8` from current `origin/main`.
- Before correction, the focused checks reproduced masked search failure.
  Capture rollback is inspected directly through `SQLiteProjectStore`, because
  the existing board snapshot loader itself bootstraps an Inbox.
- The new local-flow tests cover capture rollback, edited/removed date previews,
  menu/board persistence parity, cross-window refresh, empty versus failed
  search, and delayed-result rejection.
- Focused behavior/source checks passed (586 tests). They include failed exact
  reminder lookup and recovery, origin refresh after a committed write with a
  failed read, and explicit date choices surviving subsequent title edits.
- The native exact-PID Inbox smoke uses only an isolated DB and disabled
  Keychain. Its postconditions include capture dates, classification/undo,
  read-only knowledge preview, and search failure/retry. The earlier System
  Events traversal could not expose SwiftUI identifiers; the existing native
  AX helper supplies the canonical operation path.
- Final complete CI, current-source UI, Companion review, and hosted checks
  are merge gates. Their final results and reviewed head are recorded in the
  associated PR; the plan alone does not claim those gates passed.
