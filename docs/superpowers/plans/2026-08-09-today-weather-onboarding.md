# Today Weather and Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask for an optional display name and weather location during first onboarding, fetch WeatherKit data with explicit permission or manual-city fallback, and keep the header useful when weather is unavailable.

**Architecture:** Store only user-selected profile/location preferences in `AppSettings`. Keep WeatherKit and Core Location behind small app-side protocols so the Core tests never call Apple services. The `TodayWeatherModel` owns permission/load/cache/error state independently from the board Snapshot and exposes a small `TodayWeatherPresentation` to the header.

**Tech Stack:** Swift 6, SwiftUI, Core Location, WeatherKit, Foundation, XCTest, generated macOS Info.plist, `packaging/Suisui.entitlements`.

---

## File map

- Create: `Sources/SuisuiCore/App/WeatherLocationPreference.swift` — Codable location choice and validation.
- Modify: `Sources/SuisuiCore/App/AppSettings.swift` — preference fields and legacy defaults.
- Create: `Sources/SuisuiApp/Weather/TodayWeatherModel.swift` — state machine, cache contract, permission client protocol.
- Create: `Sources/SuisuiApp/Weather/WeatherKitTodayProvider.swift` — production `WeatherService` adapter.
- Create: `Sources/SuisuiApp/Weather/CoreLocationTodayClient.swift` — foreground location permission and one-shot coordinate client.
- Modify: `Sources/SuisuiApp/Views/OnboardingWelcomeView.swift` — `todayPersonalization` step and save/skip flow.
- Modify: `Sources/SuisuiCore/App/FirstRunOnboarding.swift` — step and transition tests.
- Modify: `Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift` — bind weather presentation and attribution link.
- Modify: `Sources/SuisuiApp/Views/SettingsFeatureViews.swift` — display name, location mode, manual city, weather refresh/clear.
- Modify: `Sources/SuisuiApp/SuisuiApp.swift` — compose production WeatherKit/Location dependencies and preserve sample-project routing.
- Modify: `packaging/Suisui.entitlements` — WeatherKit entitlement.
- Modify: `script/build_and_run.sh` — generated `Info.plist` location usage description.
- Create: `Tests/SuisuiCoreTests/WeatherLocationPreferenceTests.swift`.
- Create: `Tests/SuisuiAppTests/TodayWeatherModelTests.swift`.
- Modify: `Tests/SuisuiCoreTests/AppSettingsTests.swift` and `Tests/SuisuiCoreTests/FirstRunOnboardingTests.swift`.
- Create/update: `docs/release/weatherkit-setup.md` and `docs/release/privacy-security.md` only after the implementation is verified.

### Task 1: Add location preference and onboarding contract tests

- [ ] **Step 1: Add failing `WeatherLocationPreferenceTests.swift`.** Cover `.unset`, `.currentLocation`, and `.manual(cityLabel:latitude:longitude:)` Codable round trips, whitespace normalization, and rejection of non-finite/out-of-range coordinates.
- [ ] **Step 2: Add failing AppSettings legacy tests.** Decode JSON without display-name, capacity, or weather keys and assert safe defaults; encode a manual city without secret fields.
- [ ] **Step 3: Extend `FirstRunOnboardingTests.swift` with the exact step order.** Assert `.welcome → .todayPersonalization → .aiProvider → .finish`, `stepCount == 4`, back navigation, skip semantics, and that completion flags remain owned by the existing gate.
- [ ] **Step 4: Run focused tests and confirm missing symbol failures.**

```bash
swift test --filter SuisuiCoreTests.WeatherLocationPreferenceTests
swift test --filter SuisuiCoreTests.FirstRunOnboardingTests
```

### Task 2: Implement settings and the onboarding state model

- [ ] **Step 1: Add `WeatherLocationPreference` to `Sources/SuisuiCore/App/WeatherLocationPreference.swift`.** Implement `Codable, Equatable, Sendable`, a `normalized` property, and a `displayLabel` that never exposes raw coordinates.
- [ ] **Step 2: Add `weatherLocationPreference` to `AppSettings`.** Decode legacy settings as `.unset`; normalize `profileDisplayName`; keep `dailyWorkCapacityMinutes` behavior from Plan 2 intact.
- [ ] **Step 3: Add `todayPersonalization` to `FirstRunOnboardingStep`.** Do not change `FirstRunOnboardingGate` keys or primary-window ownership.
- [ ] **Step 4: Run AppSettings and onboarding tests and commit the Core settings model.**

```bash
swift test --filter SuisuiCoreTests.AppSettingsTests
swift test --filter SuisuiCoreTests.FirstRunOnboardingTests
git add Sources/SuisuiCore/App/WeatherLocationPreference.swift Sources/SuisuiCore/App/AppSettings.swift Sources/SuisuiCore/App/FirstRunOnboarding.swift Tests/SuisuiCoreTests/WeatherLocationPreferenceTests.swift Tests/SuisuiCoreTests/AppSettingsTests.swift Tests/SuisuiCoreTests/FirstRunOnboardingTests.swift
git diff --cached --check
git commit -m "feat: add Today weather preferences"
```

### Task 3: Define the Weather model and test all states

**Files:** Create `Sources/SuisuiApp/Weather/TodayWeatherModel.swift` and `Tests/SuisuiAppTests/TodayWeatherModelTests.swift`.

- [ ] **Step 1: Define small protocols.** `TodayLocationClient` requests when-in-use permission and returns one coordinate; `TodayWeatherProviding` fetches a `TodayWeatherValue`; `TodayWeatherCache` saves/loads the last successful value. Test doubles must be in-memory and deterministic.
- [ ] **Step 2: Add `TodayWeatherState` cases:** `.notConfigured`, `.requestingPermission`, `.loading`, `.loaded(value,isStale:)`, `.denied`, `.unavailable(reason:)`, `.failed(message:)`.
- [ ] **Step 3: Write failing tests for manual city load, current-location permission, denied permission, stale-after-30-minutes, cached-on-network-failure, and cache clear on disconnect.** Assert no location coordinate is emitted in user-facing error text.
- [ ] **Step 4: Implement `TodayWeatherModel` as `@MainActor ObservableObject`.** It resolves settings preference, asks the location client only after the user chooses current location, fetches through the provider, marks values stale after 30 minutes, and publishes a retry action. It never writes to ProjectBoard.
- [ ] **Step 5: Run the app-test target and commit the model.**

```bash
swift test --filter SuisuiAppTests.TodayWeatherModelTests
git add Sources/SuisuiApp/Weather/TodayWeatherModel.swift Tests/SuisuiAppTests/TodayWeatherModelTests.swift
git diff --cached --check
git commit -m "feat: add testable Today weather state"
```

### Task 4: Add production Core Location and WeatherKit adapters

**Files:** Create `Sources/SuisuiApp/Weather/CoreLocationTodayClient.swift` and `Sources/SuisuiApp/Weather/WeatherKitTodayProvider.swift`; modify `packaging/Suisui.entitlements` and `script/build_and_run.sh`.

- [ ] **Step 1: Implement one-shot foreground location.** Request macOS when-in-use permission only after the personalization action; stop updates after one usable coordinate; map denied/restricted/timeout into the model's explicit states.
- [ ] **Step 2: Implement WeatherKit adapter.** Call `WeatherService` with the selected coordinate, map current/high/low conditions into `TodayWeatherValue`, and expose `WeatherService.attribution` as a linkable value. Do not put developer tokens or raw responses in logs.
- [ ] **Step 3: Add `com.apple.developer.weatherkit` to `packaging/Suisui.entitlements`.** Keep existing audio entitlement unchanged.
- [ ] **Step 4: Add `NSLocationUsageDescription` to the generated Info.plist in `script/build_and_run.sh`.** Use a localized, user-facing explanation that weather uses the location only while the app is running; add a shell test or plist assertion so the key cannot disappear.
- [ ] **Step 5: Run plist/entitlement validation and focused Weather tests.**

```bash
swift test --filter SuisuiAppTests.TodayWeatherModelTests
./script/verify_bundle_metadata.sh
```

- [ ] **Step 6: Commit the production adapters and packaging changes.**

```bash
git add Sources/SuisuiApp/Weather/CoreLocationTodayClient.swift Sources/SuisuiApp/Weather/WeatherKitTodayProvider.swift packaging/Suisui.entitlements script/build_and_run.sh
git diff --cached --check
git commit -m "feat: connect Today weather to WeatherKit"
```

### Task 5: Add the personalization onboarding UI

**Files:** Modify `Sources/SuisuiApp/Views/OnboardingWelcomeView.swift`; modify `Sources/SuisuiApp/SuisuiApp.swift`; update localized strings.

- [ ] **Step 1: Add a `todayPersonalizationStep` view.** Include an optional display-name `TextField`, a location choice (`Use Current Location`, `Choose a City`, `Not Now`), a short privacy explanation, and stable identifiers `onboarding-display-name`, `onboarding-current-location`, `onboarding-manual-city`, and `onboarding-location-skip`.
- [ ] **Step 2: Change Welcome actions without breaking sample routing.** `Set up AI first` advances to personalization and records the pending path; `Try Suisui now` creates/reuses the sample, then advances to personalization before invoking the existing `onTrySuisui` routing closure.
- [ ] **Step 3: On Continue, save only normalized display/location preferences.** Do not mark onboarding dismissed until the existing finish/skip callback runs. On `Back`, restore the previous values from the view model rather than persisting intermediate text.
- [ ] **Step 4: Add tests for Try-Suisui, AI-first, skip, existing-value editing, and manual-city fallback.** Keep the existing isolated runtime smoke route intact.
- [ ] **Step 5: Run onboarding smoke and tests.**

```bash
swift test --filter SuisuiCoreTests.FirstRunOnboardingTests
./script/check_runtime_onboarding_smoke.sh
```

- [ ] **Step 6: Commit the onboarding flow.**

```bash
git add Sources/SuisuiApp/Views/OnboardingWelcomeView.swift Sources/SuisuiApp/SuisuiApp.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Tests/SuisuiCoreTests/FirstRunOnboardingTests.swift
git diff --cached --check
git commit -m "feat: collect Today preferences during onboarding"
```

### Task 6: Bind weather to Header and Settings

- [ ] **Step 1: Replace the Phase 1 weather placeholder in `TodayDashboardHeaderView`.** Show condition, temperature, location label, loading/stale/error state, retry, and a disclosure/popover containing Apple Weather attribution and legal link.
- [ ] **Step 2: Add Settings controls.** Allow switching current location/manual city/not configured, clear cached weather, and manually retry. Use existing save messaging and never display coordinates as the city name.
- [ ] **Step 3: Compose `TodayWeatherModel` once per Project Board scene in `SuisuiApp.swift`.** Avoid creating a new provider on every SwiftUI body evaluation; inject test doubles in app tests.
- [ ] **Step 4: Verify keyboard/VoiceOver labels, denied permission, offline cache, and Japanese/English `Suisui` spelling.**
- [ ] **Step 5: Commit UI and documentation.** Add `docs/release/weatherkit-setup.md` with capability, entitlement, location usage description, and attribution instructions; update `docs/release/privacy-security.md` with the no-location-history rule.

```bash
swift test
script/build_and_run.sh --verify
git add Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift Sources/SuisuiApp/Views/SettingsFeatureViews.swift Sources/SuisuiApp/SuisuiApp.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings docs/release/weatherkit-setup.md docs/release/privacy-security.md
git diff --cached --check
git commit -m "feat: show WeatherKit state in Today"
```

### Task 7: Weather verification and handoff

- [ ] **Step 1: Run `swift test` and the runtime smoke.**
- [ ] **Step 2: Capture Today in Light/Dark/System with WeatherKit disabled and with a deterministic Weather test fixture.** Confirm the entire dashboard remains usable in both cases.
- [ ] **Step 3: Run the packaging entitlement/plist checks and inspect the diff for tokens, coordinates, and accidental `Suisui` translation.**
