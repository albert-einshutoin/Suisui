# iOS Companion MVP

The Phase 13 iOS companion starts as a SwiftPM `SuisuiiOS` support module backed by `SuisuiCore`. A wrapper Xcode app can use `SuisuiiOSCompanionApp` as the SwiftUI entry point.

## Package Shape

- Package platform: `.iOS(.v17)` plus existing `.macOS(.v14)`.
- Product: `SuisuiiOS`.
- Target: `Sources/SuisuiiOS`.
- Entry type: `SuisuiiOSCompanionApp`.
- Root surface: `SuisuiiOSRootView`.

This keeps iOS UI code separate from the macOS app target while reusing the platform-neutral sync and task mutation contracts.

## Registration Flow

`IOSCompanionMVPConfiguration.default.registrationFlow` fixes the first mobile setup flow:

1. Sign in.
2. Restore entitlement.
3. Register device.
4. Enable Sync.

The mobile app should not sync or approve remote actions until entitlement restoration and device registration have completed.

## Mobile Surfaces

The MVP surface set is:

- Inbox
- Today
- Project task list
- Board-lite status controls
- Conversation
- Pending action approval inbox

`SuisuiiOSRootView` exposes those surfaces as tabs so the first screen is the task tool itself, not a landing page.

## Capture Inputs

The initial capture scope is:

- Text conversation
- Voice input
- Shortcuts create task
- Shortcuts ask Suisui
- Share Sheet capture

All write paths produce `SyncTaskMutationPayload` or approved `SyncAutomationRequestPayload` values. Local filesystem automation and arbitrary MCP execution remain out of scope for iOS.

## Task Actions

`IOSCompanionTaskAction` maps mobile actions to platform-neutral mutations:

- create task
- complete task
- change status
- change due date
- move to project

Blank title, status, and due-date inputs are rejected before mutation creation.

## Approval Inbox

`IOSPendingActionApproval.approve(_:)` moves pending cloud relay or Hosted MCP requests from `pendingApproval` to `approved` while preserving the original mutation details. Already-reviewed requests are rejected.

## Verification

Verified locally:

- `swift test --filter IOSCompanionTests`
- `swift build --target SuisuiiOS`
- `xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme SuisuiiOS -destination 'platform=macOS,variant=Mac Catalyst' build`

The pure iOS device/simulator destination could not be executed on this machine because Xcode reports that the iOS 26.5 platform is not installed. The target and scheme are present; installing the iOS platform component should allow the same scheme to build for `generic/platform=iOS`.
