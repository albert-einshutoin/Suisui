# Today Dashboard Calendar and Slack Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the read-only Calendar and Slack summaries required by the approved `today.png` layout without giving Today any write, post, read-receipt, or broad-search capability.

**Architecture:** Keep provider runtimes behind small read-only protocols. Normalize both providers into `TodayExternalActivitySnapshot`, persist only short-lived summary/cursor data, and let `TodayExternalActivityModel` own Calendar and Slack states independently. The existing Google Calendar write runtime and Slack draft/post connector remain separate and are never called from Today.

**Tech Stack:** Swift 6, SwiftUI/macOS 14, XCTest, Google Calendar REST sync tokens, Keychain-backed OAuth, Slack Web API read methods, existing SQLite settings store, existing deep-link policy.

---

## File map

- Create: `Sources/SuisuiCore/App/TodayExternalActivity.swift` — provider-neutral summaries, status values, and review-row projection.
- Create: `Sources/SuisuiCore/App/TodayExternalActivityCache.swift` — cache protocol and SQLite implementation for summaries, cursors, and selected Slack conversation IDs.
- Create: `Tests/SuisuiCoreTests/TodayExternalActivityTests.swift` — value, retention, stale/error, and review-row contracts.
- Create: `Tests/SuisuiCoreTests/TodayExternalActivityCacheTests.swift` — SQLite round-trip and disconnect deletion tests.
- Modify: `Sources/SuisuiCore/App/ExternalIntegrationIdentifiers.swift` — add the Google read-only scope and Slack read scopes as stable identifiers; keep existing write identifiers unchanged.
- Modify: `Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarAppRuntime.swift` — expose read-only scope configuration and a read client factory without changing the existing write sink.
- Create: `Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarActivityReader.swift` — list selected-calendar events and map full/incremental responses to summaries.
- Create: `Tests/SuisuiCoreTests/GoogleCalendarActivityReaderTests.swift` — request, paging, baseline, incremental, 410, duplicate, and no-write tests.
- Modify: `Sources/SuisuiCore/App/GoogleCalendarHTTPContracts.swift` — add Decodable event/list response contracts containing only fields needed by the reader.
- Create: `Sources/SuisuiExternalConnectors/SlackReadOnlyActivity.swift` — read-only Slack protocol, scope set, allowlist reader, and rate-limit handling.
- Create: `Tests/SuisuiCoreTests/SlackReadOnlyActivityTests.swift` — scope, allowlist, unread/mention, 429, and no-write tests.
- Create: `Sources/SuisuiApp/Today/TodayExternalActivityModel.swift` — independent Calendar/Slack observable state and refresh orchestration.
- Create: `Tests/SuisuiAppTests/TodayExternalActivityModelTests.swift` — provider isolation, stale fallback, retry, and deep-link mapping.
- Modify: `Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift` — compose the read-only Calendar reader with the existing credential store and cache.
- Create: `Sources/SuisuiApp/Composition/SlackRuntimeCompositionFactory.swift` — compose selected-conversation read-only Slack access; no write connector is exposed here.
- Modify: `Sources/SuisuiApp/Views/TodayDashboardCards.swift` — render external rows inside `要確認` alongside the review-task rows.
- Modify: `Sources/SuisuiApp/Views/SettingsFeatureViews.swift` and localized strings — explicit Calendar/Slack connect, selection, refresh, and disconnect controls.
- Modify: `Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift` and `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift` — freeze the Today read-only boundary and source spelling/AX contracts.
- Modify: `docs/release/privacy-security.md` and `docs/security/external-side-effect-journal.md` — document scope minimization, retained fields, and disconnect deletion.

### Task 1: Lock provider-neutral activity values and retention limits with failing tests

**Files:** Create `Sources/SuisuiCore/App/TodayExternalActivity.swift` and `Tests/SuisuiCoreTests/TodayExternalActivityTests.swift`.

- [ ] **Step 1: Write the failing summary contract.** Define the intended values in the test before adding production types.

```swift
func testExternalSnapshotKeepsCalendarAndSlackStatesIndependent() {
    let snapshot = TodayExternalActivitySnapshot(
        calendar: .fresh(.init(added: 1, changed: 2, cancelled: 0, lastUpdatedAt: fixedDate, deepLink: calendarURL)),
        slack: .failed(message: "Slack is unavailable", lastSuccessfulAt: nil)
    )

    XCTAssertEqual(snapshot.calendar.reviewTitle, "Google Calendar")
    XCTAssertEqual(snapshot.calendar.reviewDetail, "3件の予定が更新されました")
    XCTAssertEqual(snapshot.slack.status, .failed)
    XCTAssertTrue(snapshot.slack.reviewDetail.contains("利用できません"))
}

func testExternalSummariesNeverRetainMessageBodiesOrCalendarDetails() {
    let slack = TodaySlackConversationSummary(
        conversationID: "D123", name: "Design", unreadCount: 2, mentionCount: 1,
        lastUpdatedAt: fixedDate, deepLink: slackURL, unreadIsEstimated: false
    )
    let encoded = try! JSONEncoder().encode(slack)
    let text = String(decoding: encoded, as: UTF8.self)

    XCTAssertFalse(text.contains("message"))
    XCTAssertFalse(text.contains("private note"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails because the value types do not exist.**

```bash
swift test --filter SuisuiCoreTests.TodayExternalActivityTests
```

Expected: compile failure naming the missing `TodayExternalActivitySnapshot` and summary types.

- [ ] **Step 3: Add exact provider-neutral types.** Implement `TodayExternalActivityStatus` (`notConfigured`, `loading`, `fresh`, `stale`, `empty`, `failed`), `TodayCalendarActivitySummary` (added/changed/cancelled counts, last update, allowed deep link), `TodaySlackConversationSummary` (conversation ID/name, unread/mention counts, estimated flag, last update, allowed deep link), and `TodayExternalActivitySnapshot` with independent Calendar and Slack states. Keep all types `Codable, Equatable, Sendable` and do not add body, attendee, attachment, meeting URL, or raw response fields.
- [ ] **Step 4: Add review projection and retention helpers.** `reviewRows` must produce a Calendar row only for a successful non-baseline change summary and one row per selected Slack conversation with a non-zero unread/mention count. Cap retained Calendar history at 20 rows and the most recent seven days, and cap each Slack conversation at one count summary. A failed provider produces an error row, never a normal zero-count row.
- [ ] **Step 5: Add tests for zero, stale, baseline, retention, and allowlisted deep links.** Verify the first Calendar full sync has no “new changes” row, stale data keeps its prior value, and URLs outside the approved Google Calendar/Slack hosts are rejected.
- [ ] **Step 6: Run the focused suite and commit the value contract.**

```bash
swift test --filter SuisuiCoreTests.TodayExternalActivityTests
git add Sources/SuisuiCore/App/TodayExternalActivity.swift Tests/SuisuiCoreTests/TodayExternalActivityTests.swift
git diff --cached --check
git commit -m "feat: add Today external activity summaries"
```

### Task 2: Add cursor/summary cache with disconnect deletion

**Files:** Create `Sources/SuisuiCore/App/TodayExternalActivityCache.swift` and `Tests/SuisuiCoreTests/TodayExternalActivityCacheTests.swift`.

- [ ] **Step 1: Write failing cache tests.** Use a migrated in-memory SQLite connection to assert that Calendar cursor/cache, Slack cursor/cache, and selected conversation IDs round-trip, while no OAuth token or message body is written to the `settings` table.
- [ ] **Step 2: Implement `TodayExternalActivityCache`.** Define `loadCalendarState`, `saveCalendarState`, `loadSlackState`, `saveSlackState`, `loadSlackAllowlist`, `saveSlackAllowlist`, and `deleteAll`. Store only encoded provider-neutral summaries, sync cursors, provider IDs, and allowlist IDs under versioned keys. Keep token storage delegated to the existing Keychain stores.
- [ ] **Step 3: Make cache reads fail closed.** Corrupt JSON, an expired schema version, or a cursor without a matching provider ID returns no cached value and records a sanitized recoverable error; it must not be interpreted as empty activity.
- [ ] **Step 4: Test disconnect cleanup.** After saving both providers, `deleteAll` must remove all external activity keys while leaving project tasks and unrelated settings untouched.
- [ ] **Step 5: Run and commit.**

```bash
swift test --filter SuisuiCoreTests.TodayExternalActivityCacheTests
git add Sources/SuisuiCore/App/TodayExternalActivityCache.swift Tests/SuisuiCoreTests/TodayExternalActivityCacheTests.swift
git diff --cached --check
git commit -m "feat: cache Today external activity safely"
```

### Task 3: Add Google Calendar read-only scope and incremental reader

**Files:** Modify `Sources/SuisuiCore/App/ExternalIntegrationIdentifiers.swift`, `Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarAppRuntime.swift`, and `Sources/SuisuiCore/App/GoogleCalendarHTTPContracts.swift`; create `Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarActivityReader.swift` and `Tests/SuisuiCoreTests/GoogleCalendarActivityReaderTests.swift`; modify `Tests/SuisuiCoreTests/GoogleCalendarAppRuntimeTests.swift`.

- [ ] **Step 1: Write failing OAuth scope tests.** Assert that a new Today connection asks for `calendar.events.readonly` plus calendar-list read and offline access, an existing `calendar.events` credential satisfies read access, and a read-only credential is not treated as write-ready.
- [ ] **Step 2: Add the stable read-only scope and request configuration.** Preserve `eventsWrite` for the current sync path. Add `eventsReadOnly` and make the reader’s required scopes `[eventsReadOnly, calendarListReadOnly]`; only the existing explicit write-sync flow may request `eventsWrite`.
- [ ] **Step 3: Add Decodable list/event contracts with minimum fields.** Decode `id`, `summary`, `status`, `start`, `end`, `updated`, `htmlLink`, `nextPageToken`, and `nextSyncToken`; discard description, attendees, attachments, conference data, and raw JSON before the Core summary boundary.
- [ ] **Step 4: Implement `GoogleCalendarActivityReader`.** The reader must:
  - load the selected Calendar’s cursor and cache;
  - perform a full sync with stable query parameters on first connection;
  - treat the first result as baseline and return zero “changed” counts;
  - use `syncToken` on subsequent calls and preserve query parameters across pages;
  - map additions/updates/cancellations to counts, deduplicated by Event ID;
  - on HTTP 410, delete that Calendar’s cursor/cache, run a fresh baseline, and return no mass-update row;
  - match Suisui-created events through the existing idempotency/event mapping before workload aggregation; if mapping is unknown, exclude the external event from workload and emit a sanitized diagnostic;
  - make only GET requests and never call `GoogleCalendarHTTPEventClient`.
- [ ] **Step 5: Add HTTP and OAuth tests.** Assert Authorization scope failures, paging query stability, `410` re-baselining, duplicate event IDs, malformed dates, cancellation counts, read-only GET method, and that an access token value never appears in thrown errors or persisted metadata.
- [ ] **Step 6: Run focused Google tests and commit.**

```bash
swift test --filter SuisuiCoreTests.GoogleCalendarActivityReaderTests
swift test --filter SuisuiCoreTests.GoogleCalendarAppRuntimeTests
git add Sources/SuisuiCore/App/ExternalIntegrationIdentifiers.swift Sources/SuisuiCore/App/GoogleCalendarHTTPContracts.swift Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarAppRuntime.swift Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarActivityReader.swift Tests/SuisuiCoreTests/GoogleCalendarActivityReaderTests.swift Tests/SuisuiCoreTests/GoogleCalendarAppRuntimeTests.swift
git diff --cached --check
git commit -m "feat: add Google Calendar read-only activity sync"
```

### Task 4: Add Slack read-only allowlist reader and rate control

**Files:** Create `Sources/SuisuiExternalConnectors/SlackReadOnlyActivity.swift` and `Tests/SuisuiCoreTests/SlackReadOnlyActivityTests.swift`; modify `Tests/SuisuiCoreTests/SaaSConnectorTests.swift` only for shared fake-client helpers.

- [ ] **Step 1: Write failing scope and request tests.** Assert that the read client requires only the selected conversation read/history scopes, never includes `chat:write` or `search:read`, and exposes no `postMessage`, reaction, or mark-read operation.
- [ ] **Step 2: Define read-only Slack contracts.** Add `SlackReadOnlyActivityClient`, `SlackConversationActivityResponse`, `SlackHistoryPage`, and `SlackReadOnlyActivityReader`. Keep message text in memory only while counting mentions; the output contains conversation ID/name, unread count, mention count, last-read estimate, and an allowed Slack deep link.
- [ ] **Step 3: Implement allowlist enforcement.** Fetch `conversations.info` and `conversations.history` only for user-selected IDs stored by the Core cache. Reject IDs not in the allowlist before making HTTP requests. Resolve the current user ID once per refresh and count `<@USER_ID>` mentions in the in-memory page.
- [ ] **Step 4: Handle provider semantics safely.** Prefer Slack-provided DM unread values. For channels without unread metadata, count messages after `last_read` and set `unreadIsEstimated == true`. Treat an empty result as a normal zero state only after a successful response.
- [ ] **Step 5: Implement rate-limit behavior.** On HTTP 429, parse `Retry-After`, preserve the last successful summary as stale, and prevent another request until the retry deadline. Manual refresh must not bypass that deadline. Do not poll all workspace conversations.
- [ ] **Step 6: Add tests and commit.** Cover allowlist rejection without network calls, mention counting, DM unread precedence, estimated channel counts, 429 retry preservation, malformed payloads, and compile/source checks proving the read client has no write method.

```bash
swift test --filter SuisuiCoreTests.SlackReadOnlyActivityTests
git add Sources/SuisuiExternalConnectors/SlackReadOnlyActivity.swift Tests/SuisuiCoreTests/SlackReadOnlyActivityTests.swift Tests/SuisuiCoreTests/SaaSConnectorTests.swift
git diff --cached --check
git commit -m "feat: add Slack read-only activity reader"
```

### Task 5: Compose independent Calendar/Slack state in Today

**Files:** Create `Sources/SuisuiApp/Today/TodayExternalActivityModel.swift` and `Tests/SuisuiAppTests/TodayExternalActivityModelTests.swift`; modify `Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift`; create `Sources/SuisuiApp/Composition/SlackRuntimeCompositionFactory.swift`.

- [ ] **Step 1: Write failing model tests.** With fake Calendar and Slack readers, assert that a Calendar failure leaves a successful Slack summary visible, stale cache is shown during refresh, and a failed initial read is not rendered as zero activity.
- [ ] **Step 2: Implement `TodayExternalActivityModel`.** Keep `calendarState`, `slackState`, `lastSuccessfulAt`, and provider-specific errors separate. Expose `refreshCalendar()`, `refreshSlack()`, `retryCalendar()`, `retrySlack()`, and `disconnect(provider:)`. Inject a clock and readers for deterministic tests; coalesce only UI publication, never provider errors.
- [ ] **Step 3: Compose Calendar using existing credential infrastructure.** Reuse `GoogleCalendarOAuthCredentialStore`, metadata scope checks, and the existing migrated SQLite connection. The composition factory may create a read client and cache, but must not construct the write sync controller for Today.
- [ ] **Step 4: Compose Slack with explicit connection and allowlist.** Require an existing read-only credential and selected IDs. Keep Slack write connector composition on its current path; do not widen its scopes as a side effect of Today.
- [ ] **Step 5: Add disconnect behavior.** Calendar disconnect must remove Keychain tokens, OAuth metadata, cursor, and cache. Slack disconnect must remove token metadata, allowlist, cursor, and summaries. The model must publish `notConfigured` afterward.
- [ ] **Step 6: Run app/model tests and commit.**

```bash
swift test --filter SuisuiAppTests.TodayExternalActivityModelTests
git add Sources/SuisuiApp/Today/TodayExternalActivityModel.swift Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift Sources/SuisuiApp/Composition/SlackRuntimeCompositionFactory.swift Tests/SuisuiAppTests/TodayExternalActivityModelTests.swift
git diff --cached --check
git commit -m "feat: compose independent external Today state"
```

### Task 6: Add Settings connection/selection controls and safe deep links

**Files:** Modify `Sources/SuisuiApp/Views/SettingsFeatureViews.swift`, `Sources/SuisuiApp/Views/SettingsView.swift`, localized strings, and the relevant app URL/deep-link policy files; extend `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift` and add focused Settings tests if the existing target has no suitable fixture.

- [ ] **Step 1: Add failing source/UI contract tests.** Assert that Calendar and Slack controls expose connect, selected source/allowlist, refresh, disconnect, and permission explanations; Today has no write/post/mark-read action label.
- [ ] **Step 2: Implement the Calendar controls.** Show read-only status and granted scopes, allow the user to choose the Calendar, explain that write permission is separate, and route OAuth through the existing callback. Do not auto-upgrade a read-only credential.
- [ ] **Step 3: Implement Slack controls.** Start OAuth explicitly, show the selected DM/conversation allowlist, permit adding/removing a conversation, display the required read/history scope rationale, and show the provider rate-limit retry time without exposing raw responses.
- [ ] **Step 4: Gate deep links.** Route only validated `calendar.google.com`/Google Calendar URLs and `slack.com`/approved Slack workspace URLs to the system opener. Invalid or untrusted URLs must show an error and perform no open.
- [ ] **Step 5: Preserve `Suisui` spelling and localization.** Add English/Japanese labels without translating the product name; all service names remain “Google Calendar”, “Slack”, and “Suisui”.
- [ ] **Step 6: Run the focused source/settings tests and commit.**

```bash
swift test --filter SuisuiCoreTests.AppExperienceSourceTests
swift test --filter SuisuiAppTests
git add Sources/SuisuiApp/Views/SettingsFeatureViews.swift Sources/SuisuiApp/Views/SettingsView.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git diff --cached --check
git commit -m "feat: add read-only external feed settings"
```

### Task 7: Render external rows inside `要確認`

**Files:** Modify `Sources/SuisuiApp/Views/TodayDashboardCards.swift` and `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift`; modify any Today composition file needed to pass the model; extend `Tests/SuisuiAppTests/TodayExternalActivityModelTests.swift` or add a focused view contract test.

- [ ] **Step 1: Write the failing view contract.** Given one Calendar update, one Slack mention, and one provider error, assert that the review card renders both successful rows and the independent error state with stable AX identifiers, while review-task actions remain available.
- [ ] **Step 2: Add `TodayExternalActivityRows`.** Render summary counts, service name, last-updated/stale text, estimated unread annotation, and a validated Open in Calendar/Slack action. Never render message bodies or event descriptions.
- [ ] **Step 3: Preserve the approved order and compact behavior.** Keep review-task rows first, external rows after them, and move the full review card with the rail below the main column at compact width; no horizontal scrolling.
- [ ] **Step 4: Add accessibility and localization.** Use `today-review-external-calendar`, `today-review-external-slack`, and `today-review-external-error` identifiers, status text independent of color, keyboard order matching visual order, and `Suisui` unchanged in all localized strings.
- [ ] **Step 5: Run app tests and build the product.**

```bash
swift test --filter SuisuiAppTests
swift build --product Suisui
```

- [ ] **Step 6: Commit the review-card integration.**

```bash
git add Sources/SuisuiApp/Views/TodayDashboardCards.swift Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift Tests/SuisuiAppTests
git diff --cached --check
git commit -m "feat: show Calendar and Slack changes in Today review"
```

### Task 8: Security, architecture, and release verification

- [ ] **Step 1: Run all tests and inspect HTTP method boundaries.**

```bash
swift test
rg -n "POST|PUT|PATCH|DELETE|postMessage|mark.*read|reactions|search:read" Sources/SuisuiApp/Today Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarActivityReader.swift Sources/SuisuiExternalConnectors/SlackReadOnlyActivity.swift
```

Expected: no write operation in the Today reader/model/composition path; existing write implementations may remain outside that path.

- [ ] **Step 2: Run the automated runtime smoke and visual evidence.**

```bash
script/build_and_run.sh --verify
SUISUI_UI_EVIDENCE_LOCALE=english ./script/capture_ui_evidence.sh
SUISUI_UI_EVIDENCE_LOCALE=japanese ./script/capture_ui_evidence.sh
./script/check_ci_visual_gate.sh
```

- [ ] **Step 3: Inspect 1448×1086 and 1024×676 manually.** Confirm `要確認` contains review tasks plus Calendar/Slack summaries, provider errors are independent, stale labels are visible, and compact layout has no horizontal scroll.
- [ ] **Step 4: Run architecture/source checks.** Confirm the Today path does not import or instantiate `SlackConnector`, `GoogleCalendarHTTPEventSink`, or any write OAuth scope; confirm tokens, message bodies, precise location, and event details are absent from logs and SQLite cache.
- [ ] **Step 5: Update `docs/release/privacy-security.md` and `docs/security/external-side-effect-journal.md`.** Include scopes, allowlist semantics, rate-limit behavior, disconnect deletion, no-write test results, AX identifiers, and the distinction between automated smoke and manual dogfooding.
- [ ] **Step 6: Run `git diff --check`, verify the worktree is clean, and record all phase commit SHAs before merging the branch.**
