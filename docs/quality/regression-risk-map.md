# Regression Risk Map

Status: P14-001 source contract green
Owner: Quality bar for Suisui (Project Board, Inbox, Today, Settings, Voice Command, Menu Bar)
Source of truth: `tasks/Phase14-QualityRegressionHardening.md`

このドキュメントは、UI / state mutation / 永続化 / リリース証跡に対する「残risk」と
「そのriskを誰が、どの検証層でカバーしているか」を一覧化する。UI PRレビューや
release 前 quality gate の抜け漏れ検出を 1 ファイルで行うために使う。

## Scope

主要 6 画面 / 状態領域を、Project Board の layout stability 不変条件 (Phase 14 LSB
参照) とともに扱う。risk 行を追加するときは、「主操作」「状態変更」「ユーザーに
見える症状」「検証層」「owner test」を 1 行単位で必ず埋める。空欄を残したまま
マージしない。

## Verification Layers

risk 行は次の 5 層のいずれかに必ず対応付ける。複数の層にまたがるriskは
`unit+source` のように複合で記載してよい。

| Layer    | 目的                                                                     | 代表コマンド / owner                                                                  |
| -------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| unit     | ドメインロジック・validation・永続化・secret boundary の速い固定化       | `swift test --filter <TestSuite>` (例: `ProjectBoardStoreTests`)                       |
| source   | SwiftUI / AppKit / script の実装境界を静的に固定する                     | `swift test --filter AppExperienceSourceTests` (Phase 14 P14-001〜P14-006 の中核)       |
| runtime  | 実アプリを起動し、AX frame とクリックパスを検証する                       | `script/check_project_board_header_layout_smoke.sh`, `script/check_runtime_accessible_crud_smoke.sh` |
| visual   | Light / Dark / System の screenshot 証跡で見た目の退行を検出する         | `script/capture_ui_evidence.sh`, `script/check_visual_regression_smoke.sh`             |
| manual   | VoiceOver / Gatekeeper / clean environment など自動化できない品質       | `script/create_voiceover_evidence.sh`, `script/create_release_evidence.sh`             |

## Coverage Status

各 risk 行の末尾に `Coverage` を必ず書く。

- `automated` — unit / source / runtime / visual のいずれかで常時検証される
- `partial` — 一部のみ自動化済み、残りは manual-only または未着手
- `manual-only` — 自動化未対応、Phase 14 後続タスクで自動化へ戻すか判断する
- `open` — risk が記録されているだけで、まだテスト / 検証スクリプトが存在しない

### Primary screens

| Screen | 主操作 | 状態変更 | ユーザーに見える症状 | Verification layer | Owner test / script | Coverage | Follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Project Board | sidebar toggle, toolbar display mode, project selection, Board / List / Overview 切替, inspector 開閉, terminal panel 表示 | sidebar visible/hidden, header action group 位置, detail column 幅, inspector 表示 | ヘッダーアクションが trailing からずれる、列が崩れる、inspector 表示時に header が潜る | source + runtime + visual | `AppExperienceSourceTests`, `ReleasePipelineTests`, `script/check_project_board_header_layout_smoke.sh` | partial | P14-002, P14-003 |
| Inbox | item 分類, Undo, capture 取り込み | triage 状態, Undo 後状態 | 分類後に row が消える/残らない、Undo が二重発火する | unit + source + runtime | `AppExperienceSourceTests`, `InboxCaptureStoreTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial | P14-005 |
| Today | row 完了, carry-over, focus path | completion 状態, focus 順序 | 完了が Task status に反映されない、focus が tab order を破る | source + runtime | `AppExperienceSourceTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial | P14-005, P14-009 |
| Settings | Theme / Language / Provider / API key / MCP の保存 | appearance, language, provider, secret 状態 | 保存後に UI と store が乖離、Keychain 値が artifact に出る | source + runtime | `AppExperienceSourceTests`, `AppSettingsTests`, `SecretStoreTests`, `script/check_accessibility_preflight.sh` | partial | P14-005, P14-011 |
| Voice Command | record, plan 承認, transcript review | recording, plan draft, 承認 / 破棄 | API key 未設定で fake success に倒れる、承認前に書き込む | source + runtime | `AppExperienceSourceTests`, `VoiceCaptureViewModelTests`, `DraftGenerationTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial | P14-005, P14-009 |
| Menu Bar | summary 確認, Settings 直リンク, quit | summary snapshot, SettingsLink 状態 | Settings 以外の項目が混ざる、theme control が漏れる | source + visual | `AppExperienceSourceTests`, `MenuBarSummaryViewModelTests` | partial | P14-006, P14-009 |

### Project Board layout stability invariants

`Sources/SuisuiApp/Views/ProjectBoardView.swift` を中心に、以下の不変条件を source 層 +
runtime AX smoke で固定する。Phase 14 で加わった layout stability harness
(P14-002 / P14-003) はここの各行を参照する。

| Region     | 不変条件                                                                | 主要 AX identifier              | Verification layer          | Owner test / script                                                            | Coverage     |
| ---------- | ----------------------------------------------------------------------- | ------------------------------- | --------------------------- | ------------------------------------------------------------------------------ | ------------ |
| toolbar    | Native toolbar keeps Voice, Search, selection details, and semantic utility overflow reachable without a second chrome layer | `project-board-command-palette` | source + runtime            | `AppExperienceSourceTests.testProjectBoardUsesOneNativeContextualToolbarLayer`, `script/check_project_board_header_layout_smoke.sh` | automated    |
| sidebar    | Sidebar toggle mutates synchronously; frame stabilizes without delayed correction (no `DispatchQueue.main.asyncAfter`, no `Timer.scheduledTimer` retry for layout) | `project-board-sidebar`, `project-board-sidebar-toggle` | source + runtime            | `AppExperienceSourceTests.testProjectBoardHeaderLayoutBridgeAvoidsDelayedCorrectionDuringStateChanges`, `script/check_project_board_header_layout_smoke.sh` | partial      |
| detail     | Toolbar display mode preserves primary action position; Board / List / Overview 切替で header height と top offset が変わらない | `project-board-detail`         | source + runtime + visual   | `AppExperienceSourceTests.testProjectBoardToolbarDisplayModeOnlyAllowsIconAndTextOrIconOnly`, `script/check_project_board_header_layout_smoke.sh`, `script/capture_ui_evidence.sh`, `script/check_visual_regression_smoke.sh` | partial      |
| inspector  | Light / Dark / System switch does not collapse or overlap; inspector open / close 後に header が潜らない | `project-inspector`           | source + runtime + visual   | `AppExperienceSourceTests`, `script/check_project_board_header_layout_smoke.sh`, `script/capture_ui_evidence.sh`, `script/check_visual_regression_smoke.sh` | partial      |
| window     | Window resize preserves fixed dimension bounds; min / standard / wide で native toolbar / detail が押し潰されない | `project-board-command-palette`, `project-board-detail` | source + runtime            | `AppExperienceSourceTests`, `script/check_layout_stability_smoke.sh` | automated    |
| layout     | Layout correction avoids delayed animation; `Transaction.disablesAnimations = true` または同期 layout policy を layout-sensitive mutation に必ず付ける | `project-board-command-palette` | source                      | `AppExperienceSourceTests.testProjectBoardHeaderIsSharedAndColumnsUseSynchronizedBounds`, `AppExperienceSourceTests.testProjectBoardHeaderLayoutBridgeAvoidsDelayedCorrectionDuringStateChanges` | automated    |

### Click-path coverage

| Click path          | 主操作                                                              | Verification layer          | Owner test / script                                            | Coverage     | Follow-up |
| ------------------- | ------------------------------------------------------------------- | --------------------------- | -------------------------------------------------------------- | ------------ | --------- |
| project_task_crud   | 追加 / 編集 / 削除 / archive / restore                                | unit + source + runtime     | `ProjectBoardStoreTests`, `AppExperienceSourceTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial      | P14-005   |
| inbox_triage        | 分類 / Undo / capture                                                | unit + source + runtime     | `InboxCaptureStoreTests`, `AppExperienceSourceTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial      | P14-005   |
| today_complete      | row 完了 / carry-over                                                | unit + source + runtime     | `ProjectBoardStoreTests`, `AppExperienceSourceTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial      | P14-005   |
| settings_save       | Theme / Language / Provider / API key / MCP 保存                    | unit + source + runtime     | `AppSettingsTests`, `SecretStoreTests`, `AppExperienceSourceTests`, `script/check_accessibility_preflight.sh` | partial      | P14-005, P14-011 |
| voice_review        | record / plan review / 承認                                          | source + runtime            | `VoiceCaptureViewModelTests`, `AppExperienceSourceTests`, `script/check_runtime_accessible_crud_smoke.sh` | partial      | P14-005, P14-009 |

### Manual-only gates (automation back-log)

次の risk は現時点で manual-only。Phase 14 後続タスクで source / runtime / visual
のいずれかに必ず戻すか、manual-only として継続するかを `Coverage` 列で判断する。

- VoiceOver focus order (Project Board / Inbox / Today / Settings / Voice Command)
  — `script/create_voiceover_evidence.sh` で manual worksheet を残す。
  Coverage: manual-only。 Follow-up: P14-009, P14-013。
- Gatekeeper 起動確認 (release machine / clean environment) — `script/create_release_evidence.sh`。
  Coverage: manual-only。 Follow-up: P14-013。
- Competitor hands-on (競合プロダクトの UX 差分) — `script/create_competitor_hands_on_evidence.sh`。
  Coverage: manual-only。 Follow-up: P14-013。

## Baseline risks covered by Phase14 follow-ups

- destructive confirmation (project archive, task delete) が confirmation なしで
  DB mutation に到達しないことは `script/check_runtime_accessible_crud_smoke.sh`
  の pre-confirmation mutation check で固定する。 Coverage: automated。
  Follow-up: P14-005, P14-009 closed。
- persistence / migration の破損 record が Project Board 全体を Unavailable に
  しないことは `ProjectBoardStoreTests` の legacy task-shape fixture、
  dangling project fallback、corrupted priority skip / audit test で固定する。
  Coverage: automated。 Follow-up: P14-010 closed。
- secret-like pattern (API key, OAuth token, MCP secret, file path) が test
  fixture / screenshot metadata / release evidence へ漏れていないことは
  `script/check_security_regressions.sh` と release/source contract test で固定する。
  Coverage: automated。 Follow-up: P14-011 closed。
- flake quarantine 運用は `docs/quality/test-triage.md` /
  `docs/quality/flake-quarantine.md` と source test で owner/reason/expiry を固定し、
  `script/release_readiness_report.sh` の action summary が最小再現コマンドを返す。
  Coverage: automated。 Follow-up: P14-012, P14-013 closed。
- quality status dashboard (`script/quality_status_report.sh`) は Phase14 未完了項目、
  risk coverage、runtime / visual / manual evidence、推奨 verifier、次の品質gapを出力する。
  `script/release_readiness_report.sh` はこの dashboard を quality triage aid として参照するが、
  release evidence にはしない。 Coverage: automated。 Follow-up: P14-014 closed。

## How to use this map

- UI / state mutation / persistence 変更の PR では、対応する screen 行と
  layout stability 不変条件行を更新する。更新を忘れた場合、review で
  `AppExperienceSourceTests` 関連が落ちる可能性がある。
- release 前 quality gate では、`Coverage` 列が `open` のまま残っている行が
  release blocker か manual-only gate かを `release_readiness_report.sh` で
  分類する。
- 新しい risk を発見したら `Primary screens` または `Click-path coverage` に
  1 行追加し、owner test を必ず書く。`Coverage: open` のまま 2 sprint 以上
  残す場合は、後続 P14 タスクへ Follow-up を必ず書く。
