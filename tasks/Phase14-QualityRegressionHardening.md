# Phase 14: Quality Regression Hardening

目的は、SoloPM の実装済み機能を増やす前に、レイアウト、クリックパス、アクセシビリティ、永続化、セキュリティ、リリース証跡のテスト漏れを体系的に潰し、ユーザーが毎日使うプロダクトとして「一瞬の崩れ」「状態変更直後だけのズレ」「手動確認でしか見つからない退行」を継続的に検出できる品質基盤を作ること。

このPhaseは単なるテスト追加ではない。UIの責務境界、SwiftUI / AppKit 同期境界、デザイン寸法の不変条件、runtime smoke、スクリーンショット証跡、CIの失敗基準を揃え、今後のUI変更が小さなPRでも安全に進む状態を作る。

## Product Bar

- Project Board、Inbox、Today、Settings、Voice Command、Menu Bar の主要クリックパスが、unit / source / runtime AX / screenshot の複数層で検証されている。
- Sidebar表示/非表示、toolbar表示モード、window resize、Light/Dark/System切替、inspector開閉、selection変更の直後に、header / sidebar / detail / inspector / project components の座標が一瞬でも破綻しないことを検出できる。
- SwiftUI state mutation、AppKit bridge、animation、layout pass の責務が明文化され、遅延補正に依存しない。
- 失敗時に「どの画面、どのクリックパス、どの座標、どのスクリーンショット」が壊れたかをPRレビューで即確認できる。
- CIで毎回走る軽量gateと、release前に走る重いruntime/visual gateが分離されている。

## Non-Goals

- すべてのmacOSバージョンとディスプレイ構成を初回から網羅しない。
- 画像比較だけでデザイン品質を保証したことにしない。AX座標、source invariant、manual evidenceを併用する。
- フレークを単にretryで隠さない。原因分類、隔離、再現コマンド、ownerを必ず残す。
- SwiftUI標準部品の内部実装を前提にした脆いprivate API検証はしない。
- 競合プロダクトの完全なE2E再現や、外部SaaS本番連携の自動実行はこのPhaseに含めない。

## Priority Model

| Priority | 判断基準 | 対象 |
| --- | --- | --- |
| High | ユーザーに見える崩れ、主要CRUD不能、データ破損、秘密情報漏洩、CIで見逃すとrelease品質に直結するもの | P14-001, P14-002, P14-003, P14-005, P14-006, P14-009, P14-010, P14-011, P14-012 |
| Middle | 品質検出範囲を広げ、UI変更やrelease前確認の精度を上げるもの | P14-004, P14-007, P14-008, P14-013 |
| Low | 品質状態の可視化、継続運用、開発効率を上げるが、先に検出基盤が必要なもの | P14-014 |

着手順は High -> Middle -> Low とする。Highがgreenになるまで、新しい大きなUI機能追加より品質gate整備を優先する。

## Quality Architecture

| 層 | 目的 | 代表コマンド | CI方針 |
| --- | --- | --- | --- |
| Unit / domain tests | ビジネスロジック、validation、永続化、security boundaryを高速に固定する | `swift test --filter ...Tests` | PRごとに必須 |
| Source invariant tests | SwiftUI / AppKit / script の実装境界を静的に固定する | `swift test --filter AppExperienceSourceTests` | PRごとに必須 |
| Runtime AX smoke | 実アプリを起動し、クリックパスとAX座標を検証する | `script/check_runtime_accessible_crud_smoke.sh`, `script/check_project_board_header_layout_smoke.sh` | UI PRとrelease前に必須 |
| Visual screenshot smoke | Light/Dark/System、window size、主要画面の見た目を画像証跡化する | `script/capture_ui_evidence.sh` | release前に必須 |
| Manual evidence | VoiceOver、Gatekeeper、別ユーザー環境など自動化できない品質を記録する | `script/create_*_evidence.sh` | release gate |

## Layout Stability Invariants

すべてのUI変更は、次の不変条件を壊していないことを確認する。

- Header action group は detail column の右端に揃い、inspector の幅変更に引きずられない。
- Sidebar toggle 直後、次のrunloopや遅延timerを待たなくても、sidebar / detail / header / inspector の座標が一貫する。
- Toolbar display mode の切替で、Project Board 内の primary action の位置が変わらない。
- Light / Dark / System 切替直後、カード、sidebar selection、header、inspector field が重なったり消えたりしない。
- Window resize、最小幅、広幅、retina / non-retina scale で固定寸法UIが押し潰されない。
- Animation は意味のある状態変化だけに使い、layout correction のための遅延animationは使わない。

## P14-001: Regression inventory and risk map

Priority: High

### Context

テストケースを増やす前に、どの画面、状態、クリックパス、データ、外部依存がプロダクト品質上のriskかを一覧化する。ここを曖昧にすると、テストが増えても漏れが残る。

### Scope

- 対象: `docs/quality/regression-risk-map.md`, `Tests/SoloPMCoreTests`, `script/`
- Project Board、Inbox、Today、Settings、Voice Command、Menu Bar、release scripts のriskを分類する。
- 既存テストが守っていること、守っていないことを表にする。

### Tests First

- [x] `AppExperienceSourceTests` に `docs/quality/regression-risk-map.md` の存在と主要画面の記載を確認するテストを追加する。
- [x] risk map に Project Board header / sidebar / detail / inspector のlayout stability項目がない場合に失敗するテストを追加する。
- [x] risk map に unit / source / runtime / visual / manual の検証層が対応付いていない場合に失敗するテストを追加する。

### Implementation Steps

- [x] `docs/quality/regression-risk-map.md` を作る。
- [x] 画面別に「主要操作」「状態変更」「壊れるとユーザーに見える症状」「検証層」「owner test」を記録する。
- [x] 既存の `AppExperienceSourceTests` / release scripts / smoke scripts をrisk mapへ対応付ける。
- [x] 残る未検証riskを P14-002 以降のタスクへリンクする。

### Acceptance Criteria

- [x] 主要画面ごとのテストカバレッジの穴が1ファイルで分かる。
- [x] UI PRのレビュー時に、追加/変更した画面のrisk map更新漏れを検出できる。
- [x] release前の残riskが自動化不足なのか、manual-only gateなのか分類されている。

### Non-goals

- 外部SaaSの本番E2Eをrisk mapだけで完了扱いにしない。
- カバレッジ率の数値だけを品質指標にしない。

## P14-002: Layout stability measurement harness

Priority: High

### Context

一瞬のデザイン崩れは、最終状態のスクリーンショットだけでは検出できない。状態変更直後、同一runloop、短い間隔の複数サンプルでAX frameとスクリーンショットを採取し、ズレを数値で落とす必要がある。

### Scope

- 対象: `script/check_layout_stability_smoke.sh`, `script/check_project_board_header_layout_smoke.sh`, `Tests/SoloPMCoreTests/ReleasePipelineTests.swift`
- Runtime app を起動し、AX identifierから対象要素のframeを取得する共通helperを作る。
- state mutation直後の `t=0ms`, `t=50ms`, `t=150ms`, `t=300ms` のframe差分を検出する。

### Tests First

- [x] `ReleasePipelineTests` にlayout stability scriptの存在、`t=0`即時サンプル、複数サンプル、frame delta thresholdをsource-levelで確認するテストを追加する。
- [x] scriptが対象AX identifier不足をskipではなく失敗扱いにするテストを追加する。
- [x] scriptが差分artifactを `.tmp/layout-stability/` に保存することを確認するテストを追加する。
- [x] AX window一時欠落やAX traversalハングで空の `t=0` サンプルをbaselineにしないsource-levelテストを追加する。

### Implementation Steps

- [x] AX frame取得処理を reusable shell / AppleScript helper に分離する。
- [x] `project-board-header-bar`, `project-board-detail`, `project-board-sidebar`, `project-inspector` を必須identifierにする。
- [x] クリック操作直後にframeを採取し、後続sampleと比較する。
- [x] thresholdは基本 `0px`、OS差が出る箇所だけ `1px` tolerance を明示する。
- [x] 失敗時は before / immediate / after のJSONとPNGを保存する。
- [x] scriptの終了メッセージに、検証した遷移名と最大deltaを出す。
- [x] AX frame採取にtimeout付きwatchdogを入れ、詰まったサンプルはerr artifactへ分類し、window復帰後に一度だけ再試行する。

### Acceptance Criteria

- [x] Sidebar toggle直後のheader / detail / inspector frame deltaを検出できる。
- [x] Toolbar display mode切替直後のheader action frame deltaを検出できる。
- [x] Window resize直後のoverlap / clipping / frame jumpを検出できる。
- [x] 失敗時にPR reviewerが再現コマンドとartifact pathを見て判断できる。
- [x] AX採取が一時的に空/ハングしてもdiff計算のbaselineを汚さず、再試行または明示blockerとして終了できる。

### Non-goals

- 高精度な動画解析はしない。まずAX frameと短間隔スクリーンショットで実用的に検出する。
- すべてのanimationを禁止しない。layout correction目的の遅延補正を禁止する。

## P14-003: Project Board split-view and header regression suite

Priority: High

### Context

Project Board は sidebar、header、detail board、inspector、toolbar/AppKit bridge が同時に動くため、最もレイアウト退行が起きやすい。今回のヘッダー修正を個別対応で終わらせず、split-view全体の不変条件として固定する。

### Scope

- 対象: `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`, `script/check_project_board_header_layout_smoke.sh`
- Header actions、sidebar toggle、Board/List/Overview切替、inspector開閉、terminal panel表示、project selection変更を網羅する。

### Tests First

- [x] Header actionsがnative primary toolbar itemに戻ったら失敗するsource testを追加する。
- [x] Sidebar toggleがanimation有効transactionへ戻ったら失敗するsource testを追加する。
- [x] Header action groupが固定height / trailing alignment / stable AX identifierを失ったら失敗するsource testを追加する。
- [x] Runtime smokeに以下の遷移を追加する。
  - [x] sidebar visible -> hidden -> visible
  - [x] iconAndLabel -> iconOnly -> iconAndLabel
  - [x] Board -> List -> Overview -> Board
  - [x] inspector open -> close -> open
  - [x] terminal panel open -> close
  - [x] project selection change

### Implementation Steps

- [x] Project Boardの主要領域にAX identifierを追加または確認する。
- [x] smoke scriptの操作を小さな関数に分け、各遷移後に `assert_layout_stable` を呼ぶ。
- [x] Header actionsがdetail column右端に収まることを、window右端ではなくdetail frame基準で判定する。
- [x] Inspector表示時にheaderがinspector下へ潜らないことを確認する。
- [x] Board/List/Overviewの切替でheader heightとtop offsetが変わらないことを確認する。
- [x] Terminal panel表示/非表示でheader action groupが下部panelのlayout再計算に巻き込まれないことを確認する。
- [x] Project選択変更時にdetail column基準のheader action位置が維持されることを確認する。

### Acceptance Criteria

- [x] Project Boardの主要状態遷移でheader / sidebar / detail / inspectorのframe jumpが検出される。
- [x] Header action controlsが常に同じ順序とAX identifierで取得できる。
- [x] Runtime smokeで失敗した時、どの遷移でどのframeがズレたか出力される。
- [x] Project Board UI変更PRはこのsuiteをfocused verifierとして使える。

### Non-goals

- Project Boardの新機能追加はしない。
- Visual redesignはこのタスクに含めない。

## P14-004: Visual screenshot baselines with semantic tolerances

Priority: Middle

### Context

スクリーンショットは見た目の退行検知に有効だが、厳密なpixel一致だけではmacOS rendering差でフレークになる。比較する対象と許容差を意味ごとに分け、黒画面、空白、重なり、低情報量、テーマ崩れを検出する。

### Scope

- 対象: `script/capture_ui_evidence.sh`, `script/check_visual_regression_smoke.sh`, `docs/quality/visual-baselines.md`
- Project Board、Inbox、Today、Settings Overview、Settings Appearance、MCP Settings、Voice Command のLight/Dark/System baselineと、ui-samples由来のInbox Voice、Projects Overview、Schedule、Done、Settings IntegrationsのLight/Dark baselineを扱う。

### Tests First

- [x] `ReleasePipelineTests` にvisual baseline manifestの存在と対象画面リストを確認するテストを追加する。
- [x] `ui-samples/01.png` から `07.png` 由来の主要cockpit画面がvisual baseline manifestから漏れないことをテストする。
- [x] 画像が小さすぎる、黒画面、低情報量の場合にscriptが失敗するsource testを追加する。
- [x] baseline更新には明示フラグが必要で、通常実行では上書きしないことをテストする。

### Implementation Steps

- [x] `docs/quality/visual-baselines.md` に対象画面、viewport、theme、許容差、更新手順を書く。
- [x] screenshot manifestをJSONまたはMarkdown tableで定義する。
- [x] `docs/release/evidence/ui-screenshots.md` に存在するPhase12 cockpit screenshotをmanifestへ追加し、`check_visual_regression_smoke.sh` の直接検査対象にする。
- [x] capture scriptでwindow sizeとthemeを固定する。
- [x] perceptual hashまたは簡易histogramで黒画面/低情報量を検出する。
- [x] 重なり検出はAX frameと併用し、画像比較だけにしない。
- [x] baseline update時はPRにbefore/after artifactを添付する運用にする。

### Acceptance Criteria

- [x] Light/Dark/Systemで主要画面のスクリーンショット証跡が取れる。
- [x] Inbox Voice、Projects Overview、Schedule、Done、Settings Integrationsの既存Light/Dark証跡もsemantic visual smokeで検査される。
- [x] 画像が空、黒、極端に小さい、対象windowでない場合に失敗する。
- [x] baseline更新が意図的なデザイン変更としてレビューできる。
- [x] macOS rendering差で不必要にフレークしない許容差が文書化されている。

### Non-goals

- 初回から全画面全状態のgoldenを作らない。
- screenshotだけでクリックパス成功を判定しない。

## P14-005: End-to-end click-path smoke expansion

Priority: High

### Context

ユーザー体験の退行は、単体テストではなく実アプリ上の連続操作で見つかることが多い。特にProject/Task CRUD、Inbox triage、Today completion、Settings保存、Voice Command reviewは、画面間の接続が壊れると実装済みでも使えない。

### Scope

- 対象: `script/check_runtime_accessible_crud_smoke.sh`, `script/check_runtime_inbox_triage_smoke.sh`, `script/check_runtime_today_complete_smoke.sh`, `script/check_runtime_settings_save_smoke.sh`, `script/check_runtime_voice_review_smoke.sh`, `script/check_runtime_workflow_smoke.sh`, `Tests/SoloPMCoreTests/ReleasePipelineTests.swift`
- 既存CRUD smokeを拡張し、日次利用クリックパスを分けて検証する。

### Tests First

- [x] smoke scriptが isolated `SOLOPM_DATABASE_PATH` を必須にしていることをsource testで固定する。
- [x] 実行後のSQLite stateを確認し、UI操作だけ成功してDB未反映の場合に失敗するテストを追加する。
- [x] click-pathごとに `PASS/FAIL/SKIP` ではなく、失敗理由と最後に見えたwindow情報を出すことをsource testで固定する。

### Implementation Steps

- [x] `project_task_crud`、`inbox_triage`、`today_complete`、`settings_save`、`voice_review` のscenarioに分ける。
- [x] 各scenarioはisolated DB seed -> app launch -> AX操作 -> DB/assertion -> artifact保存の順で実行する。
- [x] destructive actionは必ずconfirmationを通ることを確認する。
- [x] Settings保存ではKeychain secret値そのものをartifactへ出さない。
- [x] Voice CommandはAPI key未設定時にfake successへ倒れないことを確認する。

### Acceptance Criteria

- [x] Project / Task CRUDがUIから永続DBへ反映される。
- [x] Inbox item分類とUndoが実アプリで完走する。
- [x] Today row completionがTask statusへ反映される。
- [x] Settings saveがUI stateとstore stateに反映される。
- [x] Voice Command review flowが承認前に止まり、audit logに残る。

### Non-goals

- 外部Calendar、Reminder、SaaSへの本番writeはしない。
- LLM API本番呼び出しをCIで必須にしない。

## P14-006: Synchronous UI mutation policy

Priority: High

### Context

デザインの一瞬の崩れは、state mutation、animation、AppKit layout pass、SwiftUI view updateが別々のタイミングで走る時に起こる。今後のUI実装で同じ問題を作らないため、同期的に扱うべき操作と、非同期でよい操作を設計原則として固定する。

### Scope

- 対象: `docs/adr/`, `Sources/SoloPMApp/Views`, `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`
- Sidebar toggle、toolbar display mode、split view visibility、theme switching、inspector open/close、project selection変更を対象にする。

### Tests First

- [x] UI layout correctionに `DispatchQueue.main.asyncAfter` やtimer retryを使う箇所が追加されたら失敗するsource testを追加する。
- [x] layout-sensitive state mutationが `Transaction.disablesAnimations = true` または明示的な同期layout policyを持たない場合に検出するテストを追加する。
- [x] AppKit bridgeが `layoutSubtreeIfNeeded` / `displayIfNeeded` の同期passを持つことを固定するテストを追加する。

### Implementation Steps

- [x] `docs/adr/NNNN-synchronous-ui-mutation-policy.md` を追加する。
- [x] layout-sensitive operation一覧と禁止patternを定義する。
- [x] SwiftUI state mutationは最小scopeのtransactionに閉じる。
- [x] AppKit interopは必要箇所だけに置き、View全体へ散らさない。
- [x] 遅延補正を使う場合はinitial attachmentなど例外理由をコメントとテストで固定する。

### Acceptance Criteria

- [x] 新しいUI PRが同期/非同期の判断基準を参照できる。
- [x] 遅延補正が便利な逃げ道として増えない。
- [x] Layout stability smokeとsource invariantが同じpolicyを守る。

### Non-goals

- すべてのUI animationを禁止しない。
- SwiftUI標準の描画タイミングを完全制御しようとしない。

## P14-007: Design system dimensions and overlap guards

Priority: Middle

### Context

カード、toolbar、header、sidebar row、inspector field の寸法が場当たり的だと、テキスト、アイコン、hover state、ローカライズでレイアウトが崩れる。固定すべき寸法と可変にすべき寸法をDesign Systemとして明文化し、source/runtime両方で守る。

### Scope

- 対象: `Sources/SoloPMApp/DesignSystem`, `Sources/SoloPMApp/Views`, `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`
- Header height、toolbar button size、sidebar min width、detail min width、inspector width、card min height、inline composer heightを扱う。

### Tests First

- [x] 主要UI componentのmin/max frame指定が消えた場合に失敗するsource testを追加する。
- [x] AX frameのoverlap検出をruntime smokeに追加する。
- [x] 長い日本語/英語ラベル、空状態、エラー状態でbutton textがはみ出ないfixtureを追加する。

### Implementation Steps

- [x] `ProjectBoardLayoutMetrics` のような局所的metricsを作るか、既存DesignSystemへ追加する。
- [x] magic numberを局所定数へ寄せ、なぜ固定するかコメントする。
- [x] ローカライズ文字列が長い場合はline limit、minimumScaleFactor、tooltip、label/hintのどれで処理するか決める。
- [x] Runtime smokeで主要AX frameのoverlapとnegative sizeを検出する。

### Acceptance Criteria

- [x] Header、sidebar、detail、inspector、cardsの寸法ルールがコードとテストで固定されている。
- [x] 長いラベルやempty/error stateでUIが重ならない。
- [x] Magic numberの追加がレビューで見つけやすい。

### Non-goals

- 全アプリ共通の巨大Design Systemへ先に抽象化しない。
- pixel-perfectを優先してnative macOSの柔軟性を壊さない。

## P14-008: State restoration, resize, and multi-window regression

Priority: Middle

### Context

通常操作では問題がなくても、前回終了時のwindow state、選択Project、sidebar visibility、inspector state、最小幅、複数windowで崩れることがある。起動直後と復元直後を重点的に検証する。

### Scope

- 対象: `SoloPMApp.swift`, `ProjectBoardView.swift`, launch scripts, runtime smoke
- Launch state、window size、selected destination、sidebar visibility、theme、multi-windowを扱う。

### Tests First

- [x] LaunchExperienceTestsに「保存状態がwindow-lessでもProject Boardが見える」ことを維持するテストを追加または確認する。
- [x] Runtime smokeに最小幅/標準幅/広幅でのlayout stability checkを追加する。
- [x] 前回選択Projectが削除済みの場合にsafe fallbackするテストを追加する。

### Implementation Steps

- [x] Runtime launch helperでwindow sizeを明示的に設定できるようにする。
- [x] selected destinationをseed DBとenvで制御する。
- [x] 削除済みselection、空DB、大量project、大量taskのfixtureを作る。
- [x] multi-windowが未対応の場合は、開けない/開いても独立stateになる境界をsource testで固定する。

### Acceptance Criteria

- [x] 空DB、通常DB、大量DBでProject Boardが起動する。
- [x] 最小幅/標準幅/広幅でheaderとdetailが重ならない。
- [x] 保存済みselectionが壊れていても起動不能にならない。
- [x] 起動直後にwindowが見えない退行を検出できる。

### Non-goals

- 高度なmulti-document app化はしない。
- すべてのwindow arrangementを保存/復元する機能追加はしない。

## P14-009: Accessibility and keyboard regression expansion

Priority: High

### Context

VoiceOver実機確認はmanual gateとして残るが、支援技術で使えるかの多くはsource/runtimeで事前に検出できる。UI変更のたびにlabel、hint、focus anchor、keyboard shortcutが抜け落ちない状態を作る。

### Scope

- 対象: `script/check_accessibility_preflight.sh`, `script/check_runtime_accessible_crud_smoke.sh`, `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`
- Project Board、Inbox、Today、Settings、Voice Commandのfocus pathとkeyboard pathを扱う。

### Tests First

- [x] 主要buttonがAX labelまたはhelpを失ったら失敗するruntime smokeを追加する。
- [x] Keyboard shortcutがmenu commandまたはfocused actionに接続されていることをsource testで固定する。
- [x] destructive confirmationが確認なしに実行できないことをruntime smokeで確認する。
- [x] 擬似VoiceOver harnessで、承認済みtask execution receiptにreviewed titleだけでなくreviewed detailが残らない場合は失敗するテストを追加する。
- [x] 擬似VoiceOver auditは、必須lifecycle nodeが存在してもdisabledならcoverage扱いにせず、Run approved planなどの到達不能なCRUD/実行controlをfailさせる。
- [x] 擬似VoiceOver auditは、必須lifecycle nodeがAX traversal上で逆順になった場合に失敗するテストを追加する。
- [x] 擬似VoiceOver auditは、AX identifierが重複した場合にクラッシュまたは黙認せず、曖昧なfocus targetとして失敗するテストを追加する。
- [x] 擬似VoiceOver auditは、AX identifierが空または空白だけの場合に、MCP/E2Eから到達不能なfocus targetとして失敗するテストを追加する。
- [x] 擬似VoiceOver auditは、`approved-execution-receipt` のような必須group/outline nodeが空labelの場合も、存在だけではmanual VoiceOver前提を満たさないものとして失敗するテストを追加する。
- [x] 擬似VoiceOver harnessは、required nodeが揃っていてもsnapshot内の空AX identifierやdynamic required nodeの重複findingをstep diffへ変換し、MCP/E2Eの曖昧なtargetをpass扱いしないことをテストする。
- [x] Project / Task inspectorのSave controlが長いSuggestion / Automation sectionより前にあり、編集後にcompact windowのAX/VoiceOver pathで即保存できることをsource testで固定する。

### Implementation Steps

- [x] 主要CRUDのfocus pathを `docs/quality/accessibility-focus-paths.md` に記録する。
- [x] `check_accessibility_preflight.sh --runtime` の対象画面をInbox/Today/Settingsへ広げる。
- [x] UI component追加時のAX identifier命名規則を定義する。
- [x] Manual VoiceOver worksheetとruntime AX smokeの項目を対応付ける。
- [x] `approved-execution-receipt` stepでreviewed task contentの欠落を検出し、タイトルだけの実行証跡ではmanual evidenceを再利用できないようにする。
- [x] `script/check_pseudo_voiceover_paths.sh --swift-test` をPR gateへ接続し、source markerだけでなく `AccessibilityFocusPathAuditTests` / `SoloPMHarnessTests` でMCP擬似VoiceOverロジックも検証する。
- [x] `AccessibilityFocusPathAudit` は必須nodeがdisabledの場合、存在だけでは通さず `disabledRequiredNode` として返す。
- [x] `AccessibilityFocusPathAudit` は必須nodeの相対順が崩れた場合、存在だけでは通さず `outOfOrderRequiredNode` として返す。
- [x] `AccessibilityFocusPathAudit` は重複したAX identifierを `duplicateNodeID` として返し、最初のnodeで監査を継続して後続findingも隠さない。
- [x] `AccessibilityFocusPathAudit` は空または空白だけのAX identifierを `blankNodeID` として返し、MCP/E2E automationがtargetを特定できないsnapshotをfailする。
- [x] `AccessibilityFocusPathAudit` は必須group/outline nodeのlabelが空の場合、存在だけでは通さず `unlabeledRequiredNode` として返す。
- [x] `SoloPMHarnessAccessibilityAuditRunner` はdynamic AX identifier findingを安定required node stepへ戻し、required nodeに紐づかないsnapshot findingも専用stepとしてfailさせる。
- [x] `SoloPMHarnessTaskLifecycleOperation.requiredFocusNodeIDs` と `SoloPMHarnessScenario.requiredFocusNodeIDs(for:)` で lifecycle operation と AX required node の対応をコード化し、operation list と pseudo VoiceOver focus path が将来ズレた場合にテストで落ちるようにする。
- [x] runtime accessible CRUD smoke は承認済みtask content executionを実アプリ上で実行し、SQLiteのstatus/detail更新だけでなく `approved-execution-receipt` のAX signalにreviewed title/detailが露出することを確認する。

### Acceptance Criteria

- [x] Mouse、keyboard、VoiceOver前提のAX pathで主要CRUD入口が検出できる。
- [x] destructive actionはconfirmationを経由しないとDB mutationしない。
- [x] 手動VoiceOver前に明らかなlabel/focus漏れを自動検出できる。
- [x] 承認済み実行は、対象タスクのタイトルと本文の両方がredacted receiptに残る場合だけ擬似VoiceOver gateを通過する。
- [x] runtime accessible CRUD smoke は、承認済み実行後のreceiptがVoiceOver/AXからreviewed title/detail付きで読めない場合にfailする。
- [x] 必須CRUD/実行controlはenabled状態で検出された場合だけ擬似VoiceOver gateを通過する。
- [x] 必須CRUD/実行controlはsource/runtimeから得たAX traversal順でも要求順に現れた場合だけ擬似VoiceOver gateを通過する。
- [x] 必須focus landmarkは、button/text field以外のgroup/outlineでも非空labelを持つ場合だけ擬似VoiceOver gateを通過する。
- [x] 必須CRUD/実行controlのAX identifierは一意な場合だけ擬似VoiceOver gateを通過する。
- [x] 必須CRUD/実行controlのAX identifierは空白ではない場合だけ擬似VoiceOver gateを通過する。
- [x] required node以外の空AX identifierやdynamic required nodeの重複も、harness runのstatus/diffへ反映される場合だけ擬似VoiceOver gateを通過する。
- [x] lifecycle operationを増減したとき、対応するAX required nodeを明示しないと `SoloPMHarnessTests` が失敗する。

### Non-goals

- VoiceOverの実機確認を自動テストだけで代替しない。
- すべての読み上げ文言を固定しすぎて改善しにくくしない。

## P14-010: Persistence, migration, and data-shape hardening

Priority: High

### Context

UI品質は永続データの形にも依存する。破損したtag、削除済みProject参照、古いmigration、null/blank/invalid enumがUI availabilityやlayoutに波及しないようにする。

### Scope

- 対象: `Sources/SoloPMCore/Storage`, `Tests/SoloPMCoreTests/ProjectBoardStoreTests.swift`, migration tests
- Project、Task、Artifact、Inbox capture、Settings、MCP registration、audit logを扱う。

### Tests First

- [x] 古いschemaから最新schemaへのmigration testを追加する。
- [x] invalid JSON / blank string / unknown enum / dangling foreign keyをfail-closedまたはsafe fallbackするテストを追加する。
- [x] UI ViewModelが破損recordを受け取ってもProject Board全体をUnavailableにしないテストを追加する。
- [x] タスク自動実行のLLM requestが、選択タスクのtitle/detail/status/priority/due/selection reasonをfenced redacted JSONとして渡し、タスク本文の改行や命令文が別タスク・直接実行指示に化けず、secret-like値がprovider境界へ出ないことをテストする。
- [x] タスク自動実行のLLM requestが、選択済みドキュメントから推定したpreparation checklist / draft artifact / release notes / PR planをsource-boundかつapproval-gatedなdraft outputとして渡し、external-source-only文脈とsecret-like値をprovider境界へ出さないことをテストする。
- [x] 将来のcallerがdocument deliverable draftを直接渡しても、source previewがないdraftやtask/status/due-date mutationをdocument成果物としてprovider payloadへ混ぜないことをテストする。
- [x] 将来のcallerが同じsuggested output pathを持つ複数のdocument deliverable draftを直接渡しても、provider payloadには最初のsource-bound draftだけを残し、同一ファイルへ矛盾するLLM成果物を作らせないことをテストする。
- [x] Document automation E2E harnessでも同じsuggested output pathを持つ複数のdocument deliverable draftを失敗扱いにし、provider境界へ進む前に成果物衝突を検出することをテストする。
- [x] document automationのsource document ID / title / summary / inclusion reasonがreview summaryやprovider contextへ入る前にredactされることをテストする。
- [x] document deliverable draftを直接構築またはCodable復元しても、title / suggested path / source document ID / source preview / rationaleのsecret-like値がreviewやprovider contextへ残らないことをテストする。
- [x] ProjectBoard ViewModel経由のtask automation review requestが、plannerのpriority/due-date選定、task cap、LLM budget、document deliverables、secret redactionを同じprovider境界で保持することをテストする。
- [x] future non-planner caller由来のdecisionがdone/blocked task、低優先度の期限なしtask、lookahead外taskを含んでも、LLM provider境界ではSettingsのpriority/due/status eligibilityで再フィルタされることをテストする。
- [x] future non-planner caller由来のdecisionがeligible taskを安全でない順序で渡しても、LLM provider境界ではplannerと同じpriority/due/id順へ再ソートしてからtask capを適用することをテストする。
- [x] 複数タスクのautomation reviewで1件目をapproved executionしても、残りのreview候補とredacted execution receipt historyが消えないことをテストする。
- [x] stale sync / future connector由来のdecisionがdirect execution可能だと主張しても、LLM provider境界ではreview-only / approval-requiredへ強制されることをテストする。
- [x] 前日のLLM call countが残ったhistoryでも、設定されたcalendar dayが変わればdaily LLM budgetが復帰し、当日期限タスクのreviewを誤って止めないことをテストする。
- [x] 同じ期日/優先度/rankのタスクが複数ある場合、後から追加されたタスクが古い未処理タスクをLLM review queueから押し出さないことをテストする。
- [x] 週次cadenceでは7日未満の通常reviewを止め、7日経過後はpriority/due-date候補をLLM reviewへ出し、provider payloadにも `weekly` を保持することをテストする。
- [x] manual cadenceはユーザー操作時だけreview候補をLLMへ出し、scheduled triggerからはprovider callを消費しないことをテストする。
- [x] ProjectBoard ViewModelのtask automation入口もmanual/scheduled triggerを受け取り、manual frequencyのscheduled runではreview queueもLLM budgetも消費しないことをテストする。
- [x] MCP擬似VoiceOverの軽量source-marker gateは、Swift側の `AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs` と同じ必須nodeを確認し、inline composer / task inspectorのtitle/detail fieldをbuttonだけの検査で取りこぼさない。

### Implementation Steps

- [x] Migration fixture DBを `.tmp` ではなく test resource として最小化して持つ。
- [x] 破損データの扱いを「表示除外」「repair candidate」「blocking error」に分類する。
- [x] Store layerでvalidationし、Viewでad hoc parseしない。
- [x] Repair可能なものはaudit logに残す。
- [x] Task automation prompt payloadを構造化JSONにし、title/detailはredacted済みのユーザー入力内容であってautomation instructionではないことを明示する。
- [x] Task automation prompt payloadへdocument deliverablesを追加し、ファイル生成やtask mutationはreviewed plan承認後にだけ実行できるdraft-only提案として扱う。
- [x] Task automation provider request builderでdocument deliverablesを再検証し、approval-gatedなファイル成果物かつsource preview付きのdraftだけをLLM payloadへ通す。
- [x] Task automation provider request builderでdocument deliverablesのsuggested output path衝突を正規化後に除外し、同一出力先へ複数draftを送らない。
- [x] Task automation provider request builderでdocument deliverablesの `sourceDocumentIDs` が空の場合は、source previewが存在してもLLM payloadへ通さず、成果物draftが選択済みdocument IDへ束縛されていることをprovider境界で再検証する。
- [x] SoloPMHarnessDocumentAutomationRunnerでdocument deliverableのsuggested output path一意性を独立stepとして検証し、E2E reportのdiffに衝突kindを出す。
- [x] `ScopedAutomationDocument` の初期化境界で source document ID / title / summary / inclusion reason をredactし、ファイル名・外部プレビュー・ユーザー選定理由由来のsecret-like値を後段へ渡さない。
- [x] `DocumentAutomationDeliverableDraft` と `DocumentAutomationDeliverableSource` の生成・復元境界で title / suggested path / source document ID / rationaleをredactし、保存済みJSONやfuture connector由来のdraftがprovider直前以外のreview面で漏れないようにする。
- [x] ProjectBoard ViewModelに、現在のboard snapshotと設定からreview-only `PlanningRequest` を作る入口を追加し、document deliverablesも同じredacted JSON payloadへ渡す。
- [x] Task automation provider request builderで、plannerを通らないselected taskにもSettings由来のstatus / priority / due-date / lookahead eligibilityを再適用する。
- [x] Task automation provider request builderで、plannerを通らないeligible selected taskにもpriority / due-date / local task IDの安定順序を再適用し、task capの前にurgent workが残るようにする。
- [x] ProjectBoard ViewModelにapproved execution receipt historyを追加し、複数選択reviewでは実行済みtaskだけをqueueから外す。
- [x] Task automation provider request builderでdecisionのapproval/direct-execution flagsを再信頼せず、API境界でreview-only契約を再固定する。
- [x] Task automation plannerで `lastRunAt` とreference dateのcalendar dayを比較し、日を跨いだsession/persisted historyはdaily LLM usageだけを0へ戻す。
- [x] Task automation plannerでrankが完全に同じ候補はlocal task ID昇順にし、有限のLLM review budgetが新しい同順位タスクだけに消費されないようにする。
- [x] Task automation cadenceに `weekly` を追加し、Settingsの頻度picker、英日表示、review-only provider promptへ同じ値を通す。
- [x] Task automation plannerにmanual/scheduled trigger境界を追加し、manual頻度ではbackground scheduleがLLM providerを呼ばないようにする。
- [x] ProjectBoard ViewModelのreview/planning request入口へ `TaskAutoExecutionTrigger` を通し、UI手動操作は既定manualのまま、将来のscheduled runnerは明示的にscheduledとして評価できるようにする。

### Acceptance Criteria

- [x] 既存ユーザーDBのshape差分でアプリが起動不能になりにくい。
- [x] 破損recordがある場合も、原因と対象がユーザー/ログに安全に見える。
- [x] 秘密情報やraw DB contentをerror messageへ出さない。
- [x] 承認済みtask executionは1件ずつ実行され、残りのreview queueとredacted receipt historyで実行漏れを検出できる。
- [x] LLM review対象のタスク内容がprompt injection風の本文を含んでも、選択理由・承認境界・削除禁止の契約が保持される。
- [x] ドキュメント群から作る成果物候補は、source document ID、suggested path、rationale、risk、approval requirementを持つreview-only payloadとして保持される。
- [x] Provider境界ではsource previewが欠けた成果物候補と、task/status/due-date mutation種別のdraftはdocument deliverableとして送信されない。
- [x] Provider境界ではsuggested output pathが重複する成果物候補を同時送信せず、同じファイルへの矛盾したdraft生成を防ぐ。
- [x] E2E harnessでもsuggested output pathが重複する成果物候補は失敗し、どの成果物kindが同じ出力先を争っているかdiffで分かる。
- [x] ドキュメント群から作る成果物候補は、source document title / inclusion reasonにsecret-like値が混ざってもreview summaryとprovider contextでredactedされる。
- [x] 直接構築またはCodable復元されたdocument deliverable draftでも、source document ID、suggested path、source preview、rationaleのsecret-like値がreview surfaceに残らない。
- [x] Document automation harnessはsource document IDだけでなく、成果物ごとのredacted source previewが欠ける/別文書にずれる場合もfailし、release notes / PR plan / draft artifactが正しい文書根拠に紐づくことを検証する。
- [x] ProjectBoardから生成するLLM review requestでも、未承認external sourceとsecret-like値をprovider境界へ出さず、filesystem draft outputはapproval-gatedのまま保持される。
- [x] Provider境界ではdone/blocked、低優先度の期限なし、lookahead外のtaskが混ざったdecisionを受け取っても、review-only LLM requestへ送られない。
- [x] future connectorやtestがunsafe decisionを渡しても、providerへ出るpayloadとpromptは `requiresUserApproval=true` / `allowsDirectExecution=false` のままになる。
- [x] Daily LLM budgetは前日分の履歴で恒久的に枯渇せず、翌日の最初のreviewでは当日予算を使ってpriority/due-date選定へ進める。
- [x] 同じ緊急度のタスクでは古い未処理タスクが先にreview対象となり、LLM予算とmax task capで後から入った同順位タスクが既存作業を飢餓状態にしない。
- [x] 低頻度運用ではweekly cadenceを選べ、7日未満の通常LLM reviewはthrottleされ、urgent cooldown以外で余分なprovider callを消費しない。
- [x] manual frequencyは明示的なユーザー操作でのみreviewを準備し、scheduled runではLLM budgetを消費しない。
- [x] ProjectBoardから呼ばれる将来のscheduled automationでもmanual frequencyが手動reviewとして扱われず、provider requestを作れない。

### Non-goals

- 自動修復でユーザーデータを勝手に削除しない。
- 本格的なDB admin UIは作らない。

## P14-011: Security and privacy regression suite

Priority: High

### Context

品質改善でruntime smokeやscreenshotが増えると、transcript、API key、file path、OAuth token、MCP secretをartifactへ漏らすriskも増える。テスト基盤そのものをsecurity boundaryに含める。

### Scope

- 対象: `Tests/SoloPMCoreTests`, `script/`, `.gitignore`, release evidence scripts
- Logs、screenshots、SQLite fixtures、audit logs、evidence files、temporary directoriesを扱う。

### Tests First

- [x] secret-like patternがtest fixture、screenshot metadata、release evidenceに出たら失敗するscanを追加する。
- [x] Runtime smoke artifact directoryが `.gitignore` 対象であることをテストする。
- [x] Keychain referenceとraw secretの区別をsource testで固定する。

### Implementation Steps

- [x] `script/check_security_regressions.sh` を作るか既存security grepへ統合する。
- [x] `sk-`, OAuth token風文字列、notary password、MCP token、filesystem pathの扱いを分類する。
- [x] Smoke scriptsはartifactにredaction済みsummaryだけを書く。
- [x] Screenshotは必要最小限にし、secret入力画面を撮る場合はmask状態を検証する。

### Acceptance Criteria

- [x] テスト追加が秘密情報漏洩riskを増やさない。
- [x] Runtime smoke artifactはtracked sourceへ混ざらない。
- [x] 失敗ログにAPI key/provider token/OAuth token/MCP secretが出ない。

### Non-goals

- 外部SASTサービス導入を必須にしない。
- 全ファイルパスを秘匿しすぎてdebug不能にしない。

## P14-012: Flake classification and CI quality gates

Priority: High

### Context

テストが増えるほど、フレークと本物の退行を分ける運用が必要になる。失敗をretryで消すのではなく、分類、owner、再現コマンド、隔離方針を持つ。

### Scope

- 対象: `scripts/ci.sh`, `scripts/verify.sh`, `script/release_readiness_report.sh`, `docs/quality/test-triage.md`
- PR gate、nightly/local heavy gate、release gateを分ける。

### Tests First

- [x] `scripts/ci.sh` が軽量PR gateと重いruntime gateを混同しないことをsource testで固定する。
- [x] `release_readiness_report.sh` がlayout stability smokeの結果を取り込めることをテストする。
- [x] Flake quarantine listが空でない場合、owner/reason/expiryが必要なことをテストする。

### Implementation Steps

- [x] `docs/quality/test-triage.md` にfailure categoryを書く。
- [x] `docs/quality/flake-quarantine.md` を作り、期限付きでしかskipできない運用にする。
- [x] `scripts/ci.sh` はunit/sourceを必須、runtime/visualは明示フラグで実行する。
- [x] `release_readiness_report.sh` はruntime/visual/manual evidenceを集約する。
- [x] 失敗時は最小再現コマンドをaction summaryに出す。

### Acceptance Criteria

- [x] PRでは速いテストで明確に落ちる。
- [x] UI/release前にはruntime/visual gateが実行できる。
- [x] フレークを無期限skipできない。
- [x] 失敗分類がbuild / assertion / crash / timing / environment / manual gateに分かれる。

### Non-goals

- CI時間を無制限に増やさない。
- フレークを放置するためのskip運用にしない。

## P14-013: Manual evidence to automated regression bridge

Priority: Middle

### Context

VoiceOver、競合hands-on、Gatekeeper、clean environmentなどは手動gateとして残る。ただし、手動で見つかった問題を次回も手動でしか見つけられない状態にしてはいけない。見つかった問題をsource/runtime/visualのどれかに必ず戻す。

### Scope

- 対象: `docs/release/manual-unblockers.md`, `docs/quality/manual-to-automated-regression.md`, evidence scripts
- Manual findingからregression test追加までの運用を定義する。

### Tests First

- [x] Manual evidenceにfailure noteがある場合、linked regression testまたはfollow-up issueが必要なことをreportで検出する。
- [x] `docs/quality/manual-to-automated-regression.md` が存在し、VoiceOver/Gatekeeper/competitorの戻し先を持つことをsource testで確認する。

### Implementation Steps

- [x] 手動gateごとに「自動化へ戻せる部分」「manual-onlyに残す部分」を分類する。
- [x] VoiceOverで見つかったlabel/focus問題はAX/source testへ戻す。
- [x] Gatekeeper/clean environmentで見つかった起動問題はpackaging/preflight testへ戻す。
- [x] Competitor hands-onで見つかったUX差分はPhase taskまたはproduct docへ戻す。
- [x] Release action summaryに「manual finding regression follow-up」を表示する。

### Acceptance Criteria

- [x] 手動確認で見つかった問題が、次回以降の自動検出対象になる。
- [x] manual-only gateとautomation-backlogが混ざらない。
- [x] release前に未処理manual findingが見える。

### Non-goals

- 手動確認をゼロにする。
- 競合プロダクトのUI変更追従を自動化する。

## P14-014: Quality completion dashboard

Priority: Low

### Context

品質Phaseはチェック項目が多くなるため、進捗が見えないと運用されない。テスト数ではなく、risk、coverage layer、runtime smoke、visual evidence、manual gateの状態を一覧化する。

### Scope

- 対象: `script/quality_status_report.sh`, `docs/quality/status.md`, `release_readiness_report.sh`
- Phase14の進捗、未検証risk、直近artifact、失敗コマンドを表示する。

### Tests First

- [x] status reportがrisk map、test commands、runtime artifact、manual gateを読み込むことをテストする。
- [x] 未完了P14 checkboxとrisk mapのuncovered itemがreportに出ることをテストする。
- [x] reportがsecret-like valuesを出さないことをテストする。

### Implementation Steps

- [x] `script/quality_status_report.sh` を作る。
- [x] `tasks/Phase14-QualityRegressionHardening.md` の未完了項目を集計する。
- [x] 直近のruntime/visual artifact pathを表示する。
- [x] `swift test`、focused tests、runtime smoke、visual smoke、manual evidenceの状態を分類する。
- [x] `release_readiness_report.sh` から参照できるようにする。

### Acceptance Criteria

- [x] 品質状態を1コマンドで確認できる。
- [x] 次に潰すべきテスト漏れが明確になる。
- [x] release readinessと重複せず、品質観点の補助reportとして使える。

### Non-goals

- Web dashboardを作らない。
- テスト結果を外部サービスへ送信しない。

## P14-015: Xcode preflight watchdog

Priority: High

### Context

`check_automated_release_preflight.sh` は release proof を1本で作るため、Xcode/SwiftBuildが外部ツール検出で返らない場合も無限待ちではなく、明示blockerとして止まる必要がある。

### Tests First

- [x] `ReleasePipelineTests` で automated preflight script が `SOLOPM_XCODE_PREFLIGHT_TIMEOUT_SECONDS` と `run_xcodebuild_with_timeout()` を持つことを固定する。
- [x] timeout時に `BLOCKER: Xcode build preflight timed out ...` を出すことをsource-levelで固定する。

### Implementation Steps

- [x] Xcode build preflightをwatchdog付き関数に分離する。
- [x] timeout値を正の整数として検証する。
- [x] timeout時は `xcodebuild` を終了させ、証跡を書かずにfail closedにする。
- [x] release checklistにtimeout調整envを記載する。

### Acceptance Criteria

- [x] Xcode buildが返らない場合でもrelease proof生成が無限停止しない。
- [x] timeoutは運用者が `SOLOPM_XCODE_PREFLIGHT_TIMEOUT_SECONDS` で調整できる。
- [x] timeoutした実行は automated preflight evidence を成功扱いにしない。

## Verification

Phase14の各PRは、変更範囲に応じて以下を使い分ける。

- [x] `swift test --filter AppExperienceSourceTests`
- [x] `swift test --filter ReleasePipelineTests`
- [x] `swift test --filter ProjectBoardStoreTests`
- [x] `swift test`
- [x] `bash -n script/check_project_board_header_layout_smoke.sh`
- [x] `script/check_project_board_header_layout_smoke.sh`
- [x] `script/check_layout_stability_smoke.sh`
- [x] `script/check_runtime_accessible_crud_smoke.sh`
- [x] `script/check_accessibility_preflight.sh --runtime`
- [x] `check_automated_release_preflight.sh` は seeded runtime AX smoke を30秒timeoutで実行し、起動直後のAX tree更新遅延でrelease proofがflakyに落ちないようにする。
- [x] `script/capture_ui_evidence.sh --doctor`
- [x] `script/check_visual_regression_smoke.sh`
- [x] `script/check_security_regressions.sh`
- [x] `script/quality_status_report.sh`

## Exit Gate

- [x] Risk mapが主要画面、主要状態変更、検証層、owner testを網羅している。
- [x] Project Boardのsidebar/header/detail/inspectorのlayout stability smokeが通る。
- [x] Sidebar toggle、toolbar display mode、window resize、theme switch、inspector open/closeの直後frame jumpを検出できる。
- [x] Runtime CRUD、Inbox、Today、Settings、Voice Commandの主要クリックパスがsmokeで検証される。
- [x] Visual screenshot smokeがLight/Dark/Systemの主要画面を検証し、黒画面/低情報量/対象window誤りを落とす。
- [x] Accessibility preflightが主要CRUDのlabel/help/focus/keyboard pathを検証する。
- [x] Persistence/migration/security regression suiteが破損データとsecret leakageを検出する。
- [x] Flake quarantineはowner、reason、expiryなしに追加できない。
- [x] Manual evidenceで見つかった問題を自動regressionへ戻す運用が文書化されている。
- [x] `script/quality_status_report.sh` で品質状態と残riskを確認できる。
- [x] `swift test` がgreen。
