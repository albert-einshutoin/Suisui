# 変更影響分析に基づく選択的CI

## 目的

Pull Requestで変更に関係するSwiftPMテスト、常時smoke、ビルド、source contract、security gateを先に実行し、完全な2,800件超のテストと重いUI gateを無条件に繰り返す時間・計算量を減らす。削減対象はテストの検出能力ではなく、影響がないと説明できる重複実行である。

最優先の安全契約は次のとおり。

> 安全に判定できる場合だけ選択的テスト。判定できない場合は全テスト。解析エラーや対象0件も全テスト。

planner自体のテスト、設定、出力検証が壊れた場合も完全検証を実行する。壊れたplannerをそのままmergeできないよう、完全検証後もplannerの失敗statusは維持する。

## CIの3レーン

- Pull Request: `ci/impact/analyze.py` がmerge-baseからrename/copyを含むNUL区切り差分を取得し、`selective` または `full` のJSON planを出す。選択対象に関係なくSwift build、CLI build、app build-only、source contract、security scan、`DevelopmentAutomationRuntimeSmokeTests`を実行する。
- main・develop・`release/**`・merge queue・手動実行・schedule: 差分に依存せず `./ci/run-full.sh` と全UI gateを実行する。
- release前: 既存のautomated release preflightが完全SwiftPM、runtime、visual、performanceを再実行する。選択的planはrelease証跡を代替しない。

定期完全検証は毎日 03:17 JST（GitHub Actionsでは前日18:17 UTC）に実行する。

## 判定順序

1. `.github/**`、`ci/**`、依存/lock、compiler/build/test設定、schema、DB、security、permission、共通test support、共通scriptを `ci/config/impact.json` の危険ルールで検査する。
2. manifestから対応プロジェクトを検出する。
3. SwiftPMのtarget graphを `swift package dump-package` から構築する。
4. 変更Swiftファイルの宣言symbolと参照を辿り、同一target内の上位sourceと参照testを選ぶ。
5. Package.swiftの依存関係を逆向きに辿り、影響moduleを記録する。
6. integration/E2E path ruleを加える。
7. 常時smokeを加える。
8. 変更があるのに安全なunit targetが0件、未分類、削除、graph不完全なら `full` にする。

単純なpath一致はintegration/E2Eや危険変更の補完にのみ使う。Swiftのunit testは宣言symbol参照とSwiftPM graphの両方で判定する。削除済みpathは存在を前提とする解析へ渡さない。

## 対応プロジェクト

manifest検出はSwiftPM、JavaScript/Node、Python、Go、Rust/Cargo、JVM/Maven/Gradleに対応する。現在、選択実行まで安全性を検証済みのアダプターはSwiftPMである。ほかのmanifestが混在した場合は「unsupported adapter」として全テストへフォールバックする。これは未対応言語を無視して成功させないための意図的な境界である。

SwiftPMアダプターはproject/target検出、dependency graph、宣言symbol参照による関連test選択、`swift test --filter <allowlisted-target>`、build、SwiftPM cache、危険ルールを提供する。

## アダプターの追加

1. `ci/impact/adapters/` に言語固有のproject検出、dependency graph、関連test選択を追加する。
2. `ci/impact/projects.py` のmanifest registryへproject typeとtoolを登録する。
3. shell文字列ではなくargv配列を返し、runner側でtarget名をallowlist検証する。
4. config解析失敗、graph不完全、未解決import、対象0件が必ず `full` になるfixtureを先に追加する。
5. docs-only、直接test、逆依存、integration、E2E、削除、rename、copy、shallow clone、adapter例外を `ci/tests/` へ追加する。
6. 完全runnerからplanner、`ci/config`、`ci/tests` への依存を追加しない。

tool固有処理をworkflow YAMLや共通plannerへ直接増やさず、アダプターと機械可読configの境界を維持する。

## ローカル再現

PR相当の判定と実行:

```bash
./ci/run-pr-ci.sh \
  --base-revision origin/main \
  --head-revision HEAD
```

plannerのfixture:

```bash
python3 -m unittest discover -s ci/tests -v
```

完全検証:

```bash
./ci/run-full.sh
```

手動GitHub Actionsは常に完全検証になる。ローカルで明示的に完全検証へ固定する場合:

```bash
./ci/run-pr-ci.sh \
  --base-revision HEAD \
  --head-revision HEAD \
  --force-full-reason "manual complete validation"
```

JSON planは `.tmp/ci-impact/test-plan.json`、実行履歴は `.tmp/ci-impact/execution.json` に出る。CIログではbase/head、project、adapter、変更file、影響module、unit/integration/E2E/smoke件数、strategy、fallback reasonを確認する。

## 全テストへのフォールバック

`ci/config/impact.json` が危険変更の単一source of truthである。CI/planner/config、dependency manifest/lock、compiler/build/test設定、DB/migration、schema/serialization、security、permission、共通test support、共通scriptは全件になる。

source/test削除、未分類file、base/merge-base/diff/shallow recovery失敗、manifest/graph/config/JSON解析失敗、unsupported adapter、存在しない変更source、対象test 0件も全件になる。

誤判定を見つけた場合は、見逃した失敗を再現するfixtureを先に追加し、原因に応じて危険ルール、integration/E2E rule、dependency解析、test対応を更新する。選択率を上げるために不確かなfallbackを削除しない。

## 段階導入と比較指標

導入期間中の選択可能PRでは、必須の選択レーンと `shadow full` を並行実行する。日数だけでshadowを自動解除しない。`.tmp/ci-impact/comparison.json` に次の比較指標を保存する。

- 選択/全件の実行時間と削減率
- selected target数とfull実行test数
- 双方のfailure件数
- `fullOnlyFailure`（選択は成功したがfullだけ失敗）
- strategy、fallback reason、総compute秒

`fullOnlyFailure` が1件でもあれば正式採用を止め、fixtureとruleを修正する。十分なPR母数、fallback率、判定失敗率、flaky率、コスト実績をレビューした後にだけ `shadowFull` policyを変更する。正式採用後もmain、release前、毎日scheduleは完全検証を維持する。

## キャッシュとコスト

cache keyはOS、CPU architecture、Swift major、`Package.swift`/`Package.resolved` hash、impact config/analyzer hashを含む。最初のstrategy jobだけがcacheを保存し、並列UI/shadow jobはrestore-onlyにして競合saveと余分な転送を避ける。cache hitは成功条件ではなく、破損時は通常build/testが失敗する。

ローカルのキャッシュを消すには、実行中のSwiftPM processがないことを確認してからリポジトリ内の `.build/` を削除する。GitHub Actions cacheはRepository SettingsのActions cachesから対象keyを削除する。共有runnerで無制限に並列化せず、UI gateはplanで必要な種類だけ起動する。実行時間だけでなくartifactの `totalComputeSeconds` も比較する。

## 出力とセキュリティ

planとexecutionはJSONで、test targetは英数字と `/` だけを許可し、`subprocess`へshellなしのargv配列で渡す。PRコードをcredential付きの `pull_request_target` で実行しない。test出力はpathとsecret-like値をredactし、artifactは短期保存する。完全runnerはplanner/config/testから独立し、解析系が壊れても既存の完全SwiftPM、source contract、security gateを実行できる。
