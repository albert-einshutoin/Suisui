# Phase 16: Public Alpha Launch Operations

目的は、Phase15で閉じたrelease candidateを、初回ユーザーが迷わず導入し、日常タスクで価値を試し、問題が起きた時に安全に報告できるPublic Alphaへ変換すること。ここではアプリの主要体験を「開発者が説明すれば使える」状態から「OSSユーザーがREADMEとアプリ内導線だけで試せる」状態へ上げる。

Phase16は、機能追加よりも導入、説明、権限、サポート、フィードバックの摩擦を減らす。first-run onboarding、permission education、public alpha checklist、feedback intake、support runbook、privacy boundaryを製品体験の一部として扱う。

## Product Bar

- 初回起動時に、Suisuiの役割、local-first境界、review-before-execution、AI provider設定、VoiceOver task listingの価値が短く理解できる。
- macOS permission、Keychain、Google OAuth、Gemini API keyなどの認証/権限が、どの操作で必要か、なぜ必要か、失敗時にどう直すかをアプリ内またはdocsから辿れる。
- Public Alphaの対象workflow、known limitations、feedback方法、support expectationsがREADMEとrelease notesに一致している。
- 問題報告は、secretや個人タスク内容を漏らさず、macOS version、Suisui version/build、provider設定状態、再現手順、redacted diagnosticsを含められる。
- OSSとして、Issue template、security policy、contributing guide、roadmapが現在のalpha範囲に合っている。

## Non-Goals

- Hosted SaaS、Team workspace、本番Google sync、外部投稿の自動化をAlpha必須にしない。
- ユーザー行動を無断で収集するanalyticsを入れない。
- 複雑なgrowth funnelや課金実装をこのPhaseの主目的にしない。
- サポート運用を外部サービスに依存させない。

## Priority Model

| Priority | 判断基準 | 対象 |
| --- | --- | --- |
| High | 初回ユーザーが詰まる、secret漏洩や誤解に直結する、feedback不能になるもの | P16-001, P16-002, P16-003, P16-004 |
| Middle | OSS/alphaとして期待値を合わせ、継続改善へつなげるもの | P16-005, P16-006 |
| Low | Launch後に見栄えや運用効率を上げるもの | P16-007 |

## P16-001: First-run onboarding for local-first AI PM workflow

Priority: High

### Context

Suisuiは機能が多く、初回ユーザーは何から始めるか迷いやすい。最初に価値を感じるには、タスク列挙、音声/テキスト入力、review-before-execution、Project Boardの基本導線を短く案内する必要がある。

### Scope

- 対象: `Sources/SuisuiApp`, onboarding state、README、public alpha docs
- first-run onboardingを、通常利用を邪魔しない軽量な導線として実装する。
- VoiceOver/keyboardでもonboardingを閉じられるようにする。

### Tests First

- [ ] Onboarding stateがUserDefaultsに保存され、secretやtask内容を保存しないunit testを追加する。
- [ ] first-run UIにlocal-first、review-before-execution、task listing、provider setupへの導線があることをsource testで固定する。
- [ ] VoiceOver label/hintとkeyboard close pathがあることをAX/source testで固定する。

### Implementation Steps

- [ ] onboarding domain modelをCoreに置き、UIは薄くする。
- [ ] 初回起動時だけ表示し、Settingsから再表示できるようにする。
- [ ] 最初の3操作を `Create or inspect tasks`, `Review before execution`, `Configure optional provider` に絞る。
- [ ] Gemini free-tier keyやGoogle OAuthは任意設定であり、local CRUDは無料/ローカルで動くことを明記する。
- [ ] Onboarding完了後、Project Boardのtask listへフォーカスできるようにする。

### Acceptance Criteria

- [ ] 初回ユーザーが3分以内にタスク一覧とタスク作成まで到達できる。
- [ ] OnboardingはVoiceOver/keyboardで操作できる。
- [ ] Onboardingはsecretやタスク内容を保存しない。

### Non-goals

- 長いチュートリアルや動画埋め込みを作らない。
- すべての機能を初回に説明しない。

## P16-002: Permission education and recovery paths

Priority: High

### Context

macOSアプリではKeychain、microphone、notifications、calendar、reminders、screen recording、file access、login itemなどのpermissionで詰まりやすい。Public Alphaでは、権限がない時に何ができず、どう直すかを具体的に示す必要がある。

### Scope

- 対象: Settings、permission readiness view、release docs、support runbook
- permission educationを、アプリ内のreadiness summaryとdocsの両方に配置する。
- Keychain access prompt、Google OAuth、Gemini API key、local file accessを混同しない。

### Tests First

- [ ] Settings readinessがKeychain/OAuth/API key/OS permissionを別カテゴリとして表示するsource testを追加する。
- [ ] permission denial時にsecret値やtokenを表示しないunit testを追加する。
- [ ] docsにSystem Settings復旧手順があることをQualitySourceContractTestsで固定する。

### Implementation Steps

- [ ] permission readiness modelを整理し、OS permissionとprovider credentialを分ける。
- [ ] 各permissionに `why needed`, `required for`, `how to recover`, `safe fallback` を持たせる。
- [ ] Keychain promptが繰り返し出る場合の診断手順をsupport runbookへ追加する。
- [ ] Google CalendarはOAuth authorization、GeminiはAPI keyとして別表記にする。
- [ ] Permission denied時のUIから、該当Settings paneやdocsへ移動できるようにする。

### Acceptance Criteria

- [ ] permission不足時、ユーザーは何を直せばよいか分かる。
- [ ] permission UIにsecretが出ない。
- [ ] Keychain/OAuth/API keyが混同されない。

### Non-goals

- macOSの全権限をアプリ側で自動変更しない。
- ユーザーの許可なしに外部同期を開始しない。

## P16-003: Feedback intake and redacted diagnostics

Priority: High

### Context

Public Alphaでは、不具合報告の質が改善速度を決める。ただし、Suisuiは個人タスクやAPI keyを扱うため、診断情報はredactedでなければならない。

### Scope

- 対象: Issue templates、support runbook、diagnostics export、privacy docs
- ユーザーが安全にバグ報告できるテンプレートと、任意のredacted diagnostics exportを用意する。

### Tests First

- [ ] diagnostics exportがAPI key、OAuth token、task detail raw textを含まないunit testを追加する。
- [ ] issue templateにmacOS version、Suisui version/build、provider、reproduction steps、redacted logs欄があることをsource testで固定する。
- [ ] diagnostics exportが明示操作なしに自動送信されないことをsource testで固定する。

### Implementation Steps

- [ ] `.github/ISSUE_TEMPLATE/bug_report.yml` をPublic Alpha向けに整える。
- [ ] redacted diagnostics modelをCoreに作り、app metadata、enabled provider names、permission status、last sanitized errorを含める。
- [ ] Diagnostics exportはローカルファイル保存のみとし、自動uploadしない。
- [ ] Support runbookに、報告の読み方、再現確認、security escalationを記載する。
- [ ] READMEとPublic Alpha Notesからfeedback導線へリンクする。

### Acceptance Criteria

- [ ] ユーザーが安全に再現情報を出せる。
- [ ] diagnostics exportはsecretやraw personal task contentを含まない。
- [ ] maintainerがissueを再現/分類しやすい。

### Non-goals

- telemetryを無断収集しない。
- crash reportの自動外部送信をこのPhaseで入れない。

## P16-004: Public alpha checklist and release channel

Priority: High

### Context

Alphaを出すには、release candidateのgreenだけでなく、配布ページ、versioning、download、checksum、rollback、known limitations、feedback routeがそろっている必要がある。

### Scope

- 対象: `docs/release/public-alpha.md`, `docs/release/checklist.md`, GitHub Releases draft、README
- Public Alphaとして出す前の最終チェックを明文化する。

### Tests First

- [ ] Public Alpha checklistにdownload, checksum, Gatekeeper, Sparkle, known limitations, feedback, rollbackがない場合に失敗するtestを追加する。
- [ ] release notesとpublic alpha docsのversion/build/source commitが矛盾しないtestを追加する。

### Implementation Steps

- [ ] Public Alpha checklistをrelease checklistから分離または拡張する。
- [ ] GitHub Release draftに貼る本文テンプレートを作る。
- [ ] download artifact、checksum、appcast、rollback手順を並べる。
- [ ] Known limitationsをPhase15のaccepted riskから転記する。
- [ ] Release publish前に、clean installとfirst-run onboardingを手動確認する。

### Acceptance Criteria

- [ ] Public Alpha publish前に見るべき項目が1つのチェックリストにまとまっている。
- [ ] Release notes、download、checksum、known limitations、feedback routeが一致している。
- [ ] Alphaを取り下げる/差し替える手順がある。

### Non-goals

- App Store配布をこのPhaseに含めない。

## P16-005: Support runbook and maintainer response policy

Priority: Middle

### Context

OSS alphaでは、issueへの初動がプロダクト品質に見える。どの報告をblocker、bug、question、enhancement、securityへ分けるかを決めておく。

### Scope

- 対象: `docs/release/support-runbook.md`, `CONTRIBUTING.md`, `SECURITY.md`
- Support triage、再現確認、security escalation、duplicate handling、release blocker判定を定義する。

### Tests First

- [ ] support runbookがblocker/bug/question/enhancement/security分類を持つことをsource testで固定する。
- [ ] security reportをpublic issueへ誘導しないことをdoc testで固定する。

### Implementation Steps

- [ ] Support runbookを作る。
- [ ] Issue label方針と初動テンプレートを作る。
- [ ] Release blockerの条件を、data loss、secret leak、app launch failure、primary task CRUD failure、VoiceOver blockerに絞る。
- [ ] Security reportはSECURITY.mdへ誘導する。
- [ ] Known issueを次patch releaseへ紐づける。

### Acceptance Criteria

- [ ] Maintainerが報告を迷わず分類できる。
- [ ] Security報告の導線が安全。
- [ ] Release blocker判定が一貫する。

### Non-goals

- SLAを商用サポートレベルにしない。

## P16-006: OSS contribution path for alpha users

Priority: Middle

### Context

SuisuiをOSSとして価値提供するには、ユーザーがバグ修正、docs改善、provider追加提案を出せる導線が必要。ただしsecret handlingやmacOS権限周りは危険なので、貢献範囲とreview policyを明確にする。

### Scope

- 対象: `CONTRIBUTING.md`, `docs/adr`, issue templates
- Good first issue、docs contribution、provider adapter contribution、security-sensitive contributionのルールを分ける。

### Tests First

- [ ] CONTRIBUTINGがTDD、security, privacy, review-before-execution, Keychain handlingを含むことをsource testで固定する。
- [ ] provider adapter追加時にfake/test doubleが必要であることをdocs testで固定する。

### Implementation Steps

- [ ] CONTRIBUTINGをPhase15/16の現状へ更新する。
- [ ] Good first issue候補をdocs/test/translation/UX copyへ寄せる。
- [ ] Provider adapterやOAuth変更にはADRまたはdesign noteを要求する。
- [ ] Secret handling checklistをPR templateへ追加する。

### Acceptance Criteria

- [ ] Alphaユーザーが安全な範囲で貢献できる。
- [ ] Secret/permission系のPRにreview checklistがある。

### Non-goals

- 大規模plugin marketplaceを作らない。

## P16-007: Product presentation refresh

Priority: Low

### Context

Public Alphaでは、スクリーンショット、README、release pageが古いと価値が伝わらない。Phase12/14のui-samples反映やvisual evidenceを、製品紹介に使える形へ整理する。

### Scope

- 対象: README screenshots、docs/assets、release notes
- 最新UIの安全なスクリーンショットだけを使う。

### Tests First

- [ ] README screenshot pathが存在し、secret input screenやblank imageでないことをsource/visual testで固定する。

### Implementation Steps

- [ ] visual baselineからPublic Alphaに使う画像を選ぶ。
- [ ] READMEの画像と説明をcurrent product scopeに合わせる。
- [ ] Secret入力画面や個人タスク内容を含む画像を除外する。

### Acceptance Criteria

- [ ] READMEを見ただけで主要workflowが伝わる。
- [ ] 画像にsecretや個人情報が含まれない。

### Non-goals

- マーケティングサイト全体を作らない。

## Verification

- [ ] `swift test --filter QualitySourceContractTests`
- [ ] `swift test --filter AppExperienceSourceTests`
- [ ] `swift test --filter ReleasePipelineTests`
- [ ] `script/check_security_regressions.sh`
- [ ] `script/check_visual_regression_smoke.sh`
- [ ] clean install manual check
- [ ] first-run onboarding manual VoiceOver check

## Exit Gate

- [ ] first-run onboardingが実装され、VoiceOver/keyboardで操作できる。
- [ ] permission educationがKeychain/OAuth/API key/macOS permissionを区別している。
- [ ] public alpha checklistがdownload、checksum、known limitations、feedback、rollbackを含む。
- [ ] feedback intakeとredacted diagnosticsがsecretを漏らさない。
- [ ] support runbookとsecurity escalationが整っている。
- [ ] README/Public Alpha Notes/GitHub Release draftがcurrent product scopeと一致している。
- [ ] `swift test` とsecurity regressionがgreen。
