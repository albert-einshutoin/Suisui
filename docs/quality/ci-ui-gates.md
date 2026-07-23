# CI UI quality gates

Suisuiは、source/unit/buildだけでは検出できない通常製品routeの退行を、独立したmacOS UI gateで検証する。GitHub Actionsは描画差分を安定させるため`macos-26`へ固定し、次の5 checkを常に別jobとして返す。

| Check | ローカル再現コマンド | 証明する内容 |
| --- | --- | --- |
| SwiftPM macOS | `./scripts/ci.sh swiftpm` | 全SwiftPM behavioral test、test count floor、build |
| Source contracts (supplemental) | `./scripts/ci.sh source-contracts` | source/document/script markerの補助契約。behavioral coverageの代替にはしない |
| UI Runtime (production route) | `./scripts/ci.sh ui-runtime` | PID-owned window、header/sidebar/detail、CRUD、layout、Today通常route |
| UI Visual (live baseline) | `./scripts/ci.sh ui-visual` | 隔離された33画面live capture、fresh AX receipt、baseline raster差分 |
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

SwiftPM jobは成功・失敗に関係なく、discovered/executed/skipped件数、sanitized test log、test name inventory、実件数をpropertyへ持つxUnit gate summaryを`.tmp/ci-artifacts/swiftpm`へ7日間保存する。0件、committed baseline未満、件数を抽出できない結果はfail closedとし、retryでgreenへ変えない。

各UI jobも成功・失敗に関係なく`.tmp/ci-artifacts/<lane>`を7日間保存する。対象はcapability summary、sanitized stdout/stderr、allowlist済みAX probe、seed fixtureだけを含むvisual current/diff/metrics/receipt、performance summary/samplesである。実ユーザーのHOME、SQLite、raw unified log、secret、token、API key、絶対pathをartifactへ含めない。

## Trust boundary

- workflow permissionは`contents: read`のみとする。
- `pull_request_target`でPR codeをcheckoutまたは実行しない。
- fork PRへrepository secret、provider credential、署名・notarization credentialを渡さない。
- GitHub-hosted runnerが必要capabilityを提供できない場合も、public fork codeを永続的なprivileged self-hosted runnerへ流さない。
- self-hosted fallbackはsecretなしのephemeral/JIT macOS runnerとし、trusted internal branch、`main`、手動releaseに限定する。

## Required check rollout

workflow追加後、PRと`main` pushの両方で3 UI jobを手動rerunなしに5回連続観測する。capability failureとflakeが0回で、実行時間が許容範囲に入った後、`SwiftPM macOS`を含むproduct gateを`main` branch protectionまたはmerge queueのrequired statusへ登録する。markerまたはbaselineを意図的に壊した検証PRがmerge不能になることまで確認して、required化を完了とする。Source contractsは独立表示しても、SwiftPM complete suiteの代替required checkとして扱わない。

Release preflightは同じruntime/visual/performance laneを再利用する。Visualは追跡済みcurrent PNGを読むだけではなく、そのrelease-candidate sourceから一時directoryへ再captureして比較する。recovery-only UIの成功はproduction UI gateの代替にしない。
