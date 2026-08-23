# 変更影響分析に基づく選択的CI

## 目的

Pull Requestで変更に関係するSwiftPMテスト、常時smoke、ビルド、source contract、security gateを先に実行し、完全な2,800件超のテストと重いUI gateを無条件に繰り返す時間・計算量を減らす。削減対象はテストの検出能力ではなく、影響がないと説明できる重複実行である。

最優先の安全契約は次のとおり。

> 安全に判定できる場合だけ選択的テスト。判定できない場合は全テスト。解析エラーや対象0件も全テスト。

planner自体のテスト、設定、出力検証が壊れた場合も完全検証を実行する。壊れたplannerをそのままmergeできないよう、完全検証後もplannerの失敗statusは維持する。

## CIの3レーン

- Pull Request: `ci/impact/analyze.py` がmerge-baseからrename/copyを含むNUL区切り差分を取得し、`selective` または `full` のJSON planを出す。rename/copyでは移動先だけでなく`oldPath`も危険変更・integration・E2Eルールへ照合する。選択対象に関係なくSwift build、CLI build、app build-only、source contract、security scan、`DevelopmentAutomationRuntimeSmokeTests`を実行する。
- main・develop・`release/**`・merge queue・手動実行・schedule: 差分に依存せず、plannerから独立した `./ci/run-full.sh` と全UI gateを実行する。
- version/release: `v*` のrelease tag作成時とGitHub Release公開時は、変更影響判定を使わず完全SwiftPM、source contract、security、全UI gateを実行する。
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
8. 変更があるのに安全なunit targetが0件、未分類、削除、graph不完全、またはfilterが実行0件なら `full` にする。

単純なpath一致はintegration/E2Eや危険変更の補完にのみ使う。Swiftのunit testは宣言symbol参照とSwiftPM graphの両方で判定する。削除済みpathは存在を前提とする解析へ渡さない。

## 対応プロジェクト

manifest検出はSwiftPM、JavaScript/Node、Python、Go、Rust/Cargo、JVM/Maven/Gradleに対応する。現在、選択実行まで安全性を検証済みのアダプターはSwiftPMである。ほかのmanifestが混在した場合は「unsupported adapter」として全テストへフォールバックする。これは未対応言語を無視して成功させないための意図的な境界である。

SwiftPMアダプターはproject/target検出、dependency graph、宣言symbol参照による関連test選択、`swift test --filter <allowlisted-target>`、build、SwiftPM cache、危険ルールを提供する。SwiftPMが一致しないfilterを終了コード0で返す場合があるため、runnerは出力から実行件数を検証し、0件や解析不能を成功扱いしない。

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

UI・Rust境界を含むローカル完全検証:

```bash
./ci/run-all.sh
```

UIを必要としない完全SwiftPM・source contract・securityの確認だけを行う場合は
`./ci/run-full.sh` を使う。これは `ci` 完了の代替ではない。

手動GitHub Actionsはselective判定を使わず、hosted runnerで実行可能な全laneを検証する。
ただし1024x676のhosted画面ではwide layoutを完遂できないため、UIの完全検証はローカルで次の入口を使う:

```bash
./ci/run-all.sh
```

JSON planは `.tmp/ci-impact/test-plan.json`、実行履歴は `.tmp/ci-impact/execution.json` に出る。CIログではbase/head、project、adapter、変更file、影響module、unit/integration/E2E/smoke件数、strategy、fallback reasonを確認する。executionの`targetCount`はfilter数、`executedTestCount`はSwiftPM出力から検証した実テスト件数である。

## 全テストへのフォールバック

`ci/config/impact.json` が危険変更の単一source of truthである。CI/planner/config、dependency manifest/lock、compiler/build/test設定、DB/migration、schema/serialization、security、permission、共通test support、共通scriptは全件になる。

あらゆるfile削除、未分類file、base/merge-base/diff/shallow recovery失敗、manifest/graph/config/JSON解析失敗、unsupported adapter、存在しない変更source、対象test 0件、filterが実行0件、実行件数の解析不能も全件になる。

選択runnerのsetup失敗は、完全SwiftPMを実行するだけでなくJSON plan自体を`full`へ昇格し、fallback理由と全UI gateを後続jobへ渡す。これにより、実行0件などで選択結果の信頼性が失われた後に、狭いE2E対象だけが残ることを防ぐ。

誤判定を見つけた場合は、見逃した失敗を再現するfixtureを先に追加し、原因に応じて危険ルール、integration/E2E rule、dependency解析、test対応を更新する。選択率を上げるために不確かなfallbackを削除しない。

## 実行範囲の運用

PRでは選択planが指定したunit、integration、E2Eと常時smokeだけを実行する。選択実行の裏で全件を重複実行しない。これにより、docs-onlyやdesktop UIと無関係なtarget変更で、全SwiftPMや全UI gateのコストを再投入しない。

品質は重複実行ではなく、fail-closed判定と完全検証イベントで担保する。planner/config/testの失敗、未分類、対象0件などはPR内で全件へフォールバックする。さらにmain、release branch、release tag、GitHub Release、release前preflight、毎日schedule、手動実行では完全検証を維持する。

## キャッシュとコスト

cache keyはOS、CPU architecture、Swift major、`Package.swift`/`Package.resolved` hash、impact config/analyzer hashを含む。PR strategyまたは完全検証jobだけがcacheを保存し、並列UI jobはrestore-onlyにして競合saveと余分な転送を避ける。cache hitは成功条件ではなく、破損時は通常build/testが失敗する。

ローカルのキャッシュを消すには、実行中のSwiftPM processがないことを確認してからリポジトリ内の `.build/` を削除する。GitHub Actions cacheはRepository SettingsのActions cachesから対象keyを削除する。共有runnerで無制限に並列化せず、PRのUI gateはplanで必要な種類だけ起動する。

## 出力とセキュリティ

planとexecutionはJSONで、test targetは英数字と `/` だけを許可し、`subprocess`へshellなしのargv配列で渡す。PRコードをcredential付きの `pull_request_target` で実行しない。test出力はpathとsecret-like値をredactし、artifactは短期保存する。完全runnerはplanner/config/testから独立し、解析系が壊れても既存の完全SwiftPM、source contract、security gateを実行できる。
