# Phase 17: Post-Launch Learning Loop

目的は、SuisuiをProduct-outした後に、利用実態、crash/error triage、usage feedback、roadmap、OSS contribution、release cadenceを次の開発へ戻す運用を作ること。Public Alphaは出して終わりではなく、何が価値になり、何が摩擦になり、どの改善を次のpatch/minor releaseへ入れるかを学習するための入口にする。

Phase17では、個人タスク管理アプリとしてのprivacy boundaryを守りながら、ユーザー報告、手動検証、ローカル診断、OSS issueを統合して、次の開発を迷わず優先順位付けできる状態を目指す。

## Product Bar

- post-launchのissue、manual finding、redacted diagnostics、release evidenceを1つのtriage flowで分類できる。
- crash/error triageは、secretやraw task contentを扱わず、再現手順、app version、macOS version、sanitized error、関連Phaseへ紐づく。
- usage feedbackは、VoiceOver task listing、review-before-execution、document-scoped automation、provider setup、Keychain prompt、onboarding摩擦のどこに関係するか分類される。
- roadmapは、blocker修正、alpha usability、provider reliability、sync/hosted expansion、OSS contributionへ分かれ、次のrelease cadenceに載る。
- patch release、minor alpha release、defer/rejectの判断基準が明確。

## Non-Goals

- 無断analyticsや個人タスク内容の収集をしない。
- すべての要望を即実装しない。
- Public Alpha直後にEnterprise/Team/SaaS本番化へ飛ばない。
- 手元の印象だけでroadmapを変えない。issue、manual evidence、diagnostics、competitor hands-onを根拠にする。

## Priority Model

| Priority | 判断基準 | 対象 |
| --- | --- | --- |
| High | data loss、secret leak、launch failure、primary CRUD failure、VoiceOver blocker、repeated Keychain promptなどAlpha継続に直結するもの | P17-001, P17-002, P17-003 |
| Middle | 価値検証と次releaseの優先順位付けに必要なもの | P17-004, P17-005 |
| Low | OSS/community運用と長期改善効率を上げるもの | P17-006, P17-007 |

## P17-001: Post-launch issue triage board

Priority: High

### Context

Alpha後は、バグ、質問、改善要望、security report、manual evidence follow-upが混ざる。分類が曖昧だと、release blockerが埋もれる。

### Scope

- 対象: GitHub issue labels/templates、support runbook、roadmap doc
- issueを `blocker`, `bug`, `question`, `enhancement`, `security`, `manual-evidence-follow-up`, `provider`, `accessibility`, `docs` に分類する。

### Tests First

- [ ] Issue templateとsupport runbookがpost-launch分類を持つことをsource testで固定する。
- [ ] blocker labelの条件がdata loss/secret leak/launch failure/primary CRUD/VoiceOver blockerを含むことをdocs testで固定する。

### Implementation Steps

- [ ] label taxonomyをdocs化する。
- [ ] Support runbookにpost-launch triage flowを追加する。
- [ ] manual evidence findingをissueへ戻すテンプレートを作る。
- [ ] 各issueにaffected version/build/source commitを要求する。
- [ ] Triage結果をroadmap更新へ渡す。

### Acceptance Criteria

- [ ] Alpha後の報告が迷わず分類される。
- [ ] Release blockerが見落とされない。
- [ ] Manual findingが自動regressionまたはexplicit deferへ戻る。

### Non-goals

- GitHub Projectsの複雑な自動化を必須にしない。

## P17-002: Crash/error triage without secret leakage

Priority: High

### Context

crashやprovider errorは最重要のpost-launch signalだが、SuisuiはAPI key、OAuth token、個人タスク内容を扱う。診断に必要な情報と漏らしてはいけない情報を明確に分ける。

### Scope

- 対象: diagnostics export、error sanitizer、support runbook、security tests
- crash/error triageに必要な最小情報をredactedで収集する。

### Tests First

- [ ] error sanitizerがAPI key、OAuth token、Bearer token、secret-like pathをredactするunit testを追加する。
- [ ] diagnostics exportにraw task detailやdocument bodyが含まれないことをfixture testで固定する。
- [ ] crash/error report templateにreproduction stepsとsanitized logs欄があることをsource testで固定する。

### Implementation Steps

- [ ] Sanitized error envelopeを定義する。
- [ ] Provider/API/Keychain/OAuth/SQLite/migration/AX smokeのerror categoryを整理する。
- [ ] Diagnostics exportへversion/build/macOS/provider configured state/permission state/sanitized errorを含める。
- [ ] Raw logsやsecretを添付しない報告手順をsupport runbookへ書く。
- [ ] Security-sensitive reportはSECURITY.mdへ誘導する。

### Acceptance Criteria

- [ ] Crash/error調査に必要な情報がsecretなしで集まる。
- [ ] Secret leakageがテストで検出される。
- [ ] Maintainerが再現/分類/修正PRへ進める。

### Non-goals

- 外部crash reporting SaaSを必須導入しない。

## P17-003: Primary workflow regression intake

Priority: High

### Context

post-launchで最優先に守るべきは、タスク列挙、作成、編集、削除、内容実行、review-before-execution、document deliverable draft、provider setupである。報告を受けたら、同じ問題を次回自動検出できるように戻す。

### Scope

- 対象: `docs/quality/manual-to-automated-regression.md`, `Tests/SuisuiCoreTests`, runtime smoke scripts
- user-reported workflow failureをunit/source/runtime/visual/manualのどこへ戻すか決める。

### Tests First

- [ ] Regression intake docがtask listing/create/edit/delete/execute/document deliverable/provider setupの戻し先を持つことをsource testで固定する。
- [ ] new regression issue templateにexpected/actual/reproduction/proposed test layerがあることをtestで固定する。

### Implementation Steps

- [ ] Workflow failure分類表を作る。
- [ ] VoiceOver task listing failureはAccessibilityFocusPathAuditまたはmanual VoiceOver worksheetへ戻す。
- [ ] CRUD/data failureはProjectTaskKnowledgeToolTestsまたはruntime CRUD smokeへ戻す。
- [ ] Document deliverable failureはDocumentScopedAutomationTests/SuisuiHarnessTestsへ戻す。
- [ ] Provider setup failureはKeychain/provider readiness testsへ戻す。
- [ ] すべてのbug fix PRにregression testを要求する。

### Acceptance Criteria

- [ ] User-reported bugが再発防止テストへ変換される。
- [ ] Manual-onlyに残す理由が明確。
- [ ] Primary workflowの退行が次releaseで見逃されにくい。

### Non-goals

- すべてのUI要望をregression扱いにしない。

## P17-004: Usage feedback synthesis and roadmap update

Priority: Middle

### Context

Alphaの価値検証では、何が使われ、何が分かりにくく、何が不要だったかを整理する必要がある。ただし、無断analyticsは使わない。GitHub issue、manual interviews、redacted diagnostics、hands-on notesから判断する。

### Scope

- 対象: roadmap doc、product role docs、competitor benchmark、feedback notes
- usage feedbackを価値仮説ごとに分類する。

### Tests First

- [ ] Roadmap docがVoiceOver task listing、review-before-execution、document automation、provider setup、sync/hosted expansionの軸を持つことをsource testで固定する。
- [ ] feedback synthesisに個人タスク内容やsecret-like valuesが入らないsecurity testを追加する。

### Implementation Steps

- [x] `docs/product/roadmap.md` を作る。
- [ ] Feedbackを `ship`, `improve`, `defer`, `reject`, `research` に分類する。
- [ ] 競合hands-onとuser feedbackを比較し、差分をroadmapへ反映する。
- [ ] 次releaseで必ず直すもの、調査するもの、やらないものを分ける。
- [ ] Roadmap更新時は根拠issue/evidenceをリンクする。

### Acceptance Criteria

- [ ] 次に何を作るべきかが根拠付きで分かる。
- [ ] 個人タスク内容をroadmapへ持ち込まない。
- [ ] RoadmapがPhase18以降の候補へつながる。

### Non-goals

- ユーザー数や利用回数だけで成功判定しない。

## P17-005: Release cadence and patch train

Priority: Middle

### Context

Alpha後は、緊急修正、通常patch、minor alphaを分ける必要がある。すべてを次の大きなPhaseへ積むと、ユーザーに必要な修正が遅れる。

### Scope

- 対象: release checklist、versioning policy、CHANGELOG/release notes
- patch releaseとminor alpha releaseの判断基準を作る。

### Tests First

- [ ] Release docsがhotfix/patch/minor alphaの判断基準を持つことをsource testで固定する。
- [ ] release notes templateがfixed/changed/known limitations/verificationを含むことをtestで固定する。

### Implementation Steps

- [ ] Release cadence docを作る。
- [ ] Hotfix条件をdata loss/secret leak/launch failure/primary CRUD/VoiceOver blockerに限定する。
- [ ] Patch releaseにはregression testとfocused verificationを必須にする。
- [ ] Minor alphaにはroadmap itemとmanual evidence refreshを要求する。
- [ ] Old release rollback手順を保守する。

### Acceptance Criteria

- [ ] 緊急修正と通常改善を分けて出せる。
- [ ] 各releaseに検証結果とknown limitationsがある。
- [ ] Release cadenceがroadmapとsupport runbookに繋がる。

### Non-goals

- 毎日releaseを義務化しない。

## P17-006: OSS contribution review loop

Priority: Low

### Context

OSSとしての価値を上げるには、外部PRを受けられる状態が必要。ただしSuisuiはsecret、Keychain、LLM、OAuth、MCP実行境界を扱うため、review policyを強くする。

### Scope

- 対象: CONTRIBUTING、PR template、ADR process、security policy
- PR種別ごとのreview focusを整理する。

### Tests First

- [ ] PR templateがTDD/manual verification/security/privacy/self reviewを含むことをsource testで固定する。
- [ ] CONTRIBUTINGがprovider/Keychain/OAuth/MCP変更にADRまたはdesign noteを要求することをdocs testで固定する。

### Implementation Steps

- [ ] PR templateをPublic Alpha向けに更新する。
- [ ] docs-only、test-only、UI、provider、storage、release scriptのreview focusを分ける。
- [ ] Security-sensitive changeは追加reviewを要求する。
- [ ] Good first issueをdocs/test/UI copy中心にする。

### Acceptance Criteria

- [ ] 外部PRでも安全境界を確認できる。
- [ ] Provider/secret/MCP変更が軽くreviewされない。

### Non-goals

- Maintainer負荷の高い大型plugin制度を作らない。

## P17-007: Provider cost and reliability learning

Priority: Low

### Context

Gemini free-tier live smokeや他providerのskip/pass/failは、Alpha後のprovider選定に役立つ。ただし無料枠を浪費せず、ユーザーのkeyやquotaを保護する必要がある。

### Scope

- 対象: provider smoke docs、quality status、roadmap
- providerごとのreliability、quota skip、cost riskをredactedに記録する。

### Tests First

- [ ] Provider smoke summaryがAPI keyやraw prompt/responseを出さないsecurity testを追加する。
- [ ] Gemini free-tier live smokeのskip/pass/failがroadmap inputとして分類されることをsource testで固定する。

### Implementation Steps

- [ ] Provider smoke result schemaを定義する。
- [ ] pass/skip/fail reasonを `configured`, `quota`, `temporary_provider_error`, `network`, `validation_failure` に分ける。
- [ ] Gemini無料枠の使用回数を手元メモまたはartifactで確認し、過剰実行しない。
- [ ] Roadmapにprovider reliabilityの改善候補を反映する。

### Acceptance Criteria

- [ ] Provider信頼性をsecretなしで比較できる。
- [ ] Gemini無料枠を無駄に消費しない。
- [ ] Provider failureがproduct UX改善へ戻る。

### Non-goals

- Provider benchmarkを大量tokenで行わない。

## Verification

- [ ] `swift test --filter QualitySourceContractTests`
- [ ] `swift test --filter ReleasePipelineTests`
- [ ] `swift test --filter AppExperienceSourceTests`
- [ ] `script/check_security_regressions.sh`
- [ ] issue template/support runbook source checks
- [ ] post-launch triage dry run with a synthetic redacted issue

## Exit Gate

- [ ] post-launch issue triage boardとlabel taxonomyがある。
- [ ] crash/error triageがsecretやraw task contentを漏らさない。
- [ ] primary workflow regression intakeがtask listing/create/edit/delete/execute/document/provider setupをカバーする。
- [ ] usage feedbackからroadmapを更新する手順がある。
- [ ] release cadenceがhotfix/patch/minor alphaを分ける。
- [ ] OSS contribution review loopがsecret/Keychain/OAuth/MCP変更を厳格に扱う。
- [ ] provider reliability/cost feedbackが無料枠保護とともにroadmapへ戻る。
- [ ] `swift test` とsecurity regressionがgreen。
