# CI UI quality gates

変更影響分析、選択的SwiftPM test、fail-closed full fallback、shadow比較の運用は
[`selective-ci.md`](./selective-ci.md) を参照する。本書のproduction UI evidence契約は、
選択的CIでも全件CIでも変わらない。

Suisuiは、source/unit/buildだけでは検出できない通常製品routeの退行を、独立したmacOS UI gateで検証する。GitHub Actionsは描画差分を安定させるため`macos-26`へ固定し、次の5 product checkを返す。Performanceはさらに、Release build用jobと測定用jobを分離する。

| Check | ローカル再現コマンド | 証明する内容 |
| --- | --- | --- |
| SwiftPM macOS | `./scripts/ci.sh swiftpm` | 全SwiftPM behavioral test、test count floor、build |
| Source contracts (supplemental) | `./scripts/ci.sh source-contracts` | source/document/script markerの補助契約。behavioral coverageの代替にはしない |
| UI Runtime (production route) | `./scripts/ci.sh ui-runtime` | PID-owned window、header/sidebar/detail、CRUD、layout、Today通常route |
| UI Visual (live baseline) | `./scripts/ci.sh ui-visual` | 英日それぞれ隔離された39枚のlive capture、locale別fresh AX receipt、baseline raster差分 |
| UI Performance (production route) | `./scripts/ci.sh ui-performance` | 通常route cold launchとInbox/Assistant Queue/Today切替budget |

UI laneは同じWindowServer session上で同時実行しない。`scripts/ci.sh`がhost-wide lockを取得し、各harnessは自分が起動したexact PIDだけを終了する。`build-only`や`verify`が、別bundleや開発者が起動中のSuisuiを名前だけで終了してはならない。

## Runner requirements

UI laneは最初にrunner capabilityをfail closedで確認する。

- console GUI sessionとWindowServerが利用できる
- Accessibility APIが許可されている
- `osascript`からSystem Eventsを操作できる
- Runtime laneではlayout screenshot用のScreen Recording、Visual laneでは加えてvisible-pixel captureも利用できる
- Swift、Swift compiler、SQLite、AppleScript、screencapture等の必要commandがある

不足をskipや成功へ変換しない。`runner-capability`として失敗させ、アプリの`launch`、`window`、`accessibility`、`product-marker`、`visual-diff`、`performance-budget`と区別する。

## Artifacts

SwiftPM jobは証跡のsource commitをPR merge commitから正しく辿るためfull git historyをcheckoutし、security/release scriptsのallowlisted search toolとして`rg`を明示的に用意する。成功・失敗に関係なく、XCTestとSwift Testingの両方を合算したdiscovered/executed/skipped件数、sanitized test log、test name inventory、実件数をpropertyへ持つxUnit gate summaryを`.tmp/ci-artifacts/swiftpm`へ7日間保存する。0件、committed baseline未満、探索件数より少ない実行件数、`config/quality/swiftpm-max-skipped-tests.txt`の上限を超えたskip、件数を抽出できない結果はfail closedとし、retryでgreenへ変えない。

各UI jobも成功・失敗に関係なく`.tmp/ci-artifacts/<lane>`を7日間保存する。Visual laneは`en-US`と`ja-JP`を独立したmatrix artifactとして保存し、既存required check名`UI Visual (live baseline)`のaggregate jobが両方の成功を要求する。PR selectorで明示的な`false`が返った場合だけmatrixをskipし、空・未知・不正な値は省略理由として扱わずfail closedにする。対象はcapability summary、sanitized stdout/stderr、allowlist済みAX probe、seed fixtureだけを含むvisual current/diff/metrics/receipt、performance summary/samplesである。実ユーザーのHOME、SQLite、raw unified log、secret、token、API key、絶対pathをartifactへ含めない。

Performance build jobが作る`.app.tar.gz`と4行manifestは、同一run/attempt内だけで1日保持する中間artifactである。測定jobはfresh `macos-26` VMで、manifestのsource commit・Release構成・SHA-256を検証し、archive entry、special file、app外へ解決するsymlinkを拒否してから展開する。検証済みmanifestとverification receiptはperformance diagnosticsへ複製し、測定結果とともに7日間保存する。これによりRelease compilerのCPU・thermal履歴をcold-launch計測VMへ持ち込まず、artifact provenanceも後から監査できる。

release readinessは、追跡済みの英日各39枚もlocale別manifestとbaseline metadataへ結び付け、既存semantic raster thresholdで再比較する。この比較は保存済み証跡を読むだけの`--raster-only` modeでありbaseline更新を禁止する。fresh AX receiptを省略できるのはこのread-only再検証だけで、hosted live captureとbaseline更新では引き続きsource/contextに一致するfresh AX receiptを必須とする。

## Trust boundary

- workflow permissionは`contents: read`のみとする。
- `pull_request_target`でPR codeをcheckoutまたは実行しない。
- fork PRへrepository secret、provider credential、署名・notarization credentialを渡さない。
- GitHub-hosted runnerが必要capabilityを提供できない場合も、public fork codeを永続的なprivileged self-hosted runnerへ流さない。
- self-hosted fallbackはsecretなしのephemeral/JIT macOS runnerとし、trusted internal branch、`main`、手動releaseに限定する。

## Required check rollout

workflow追加後、PRと`main` pushの両方で3 UI jobを手動rerunなしに5回連続観測する。capability failureとflakeが0回で、実行時間が許容範囲に入った後、`SwiftPM macOS`を含むproduct gateを`main` branch protectionまたはmerge queueのrequired statusへ登録する。markerまたはbaselineを意図的に壊した検証PRがmerge不能になることまで確認して、required化を完了とする。Source contractsは独立表示しても、SwiftPM complete suiteの代替required checkとして扱わない。

Release preflightは同じruntime/visual/performance laneを再利用する。Visualは追跡済みcurrent PNGを読むだけではなく、そのrelease-candidate sourceから一時directoryへ再captureして比較する。recovery-only UIの成功はproduction UI gateの代替にしない。
