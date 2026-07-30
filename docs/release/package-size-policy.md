# Package Size Policy

Suisuiの配布物は、初回導入が軽く、必要な高度機能はユーザーが選んだときだけ追加取得する構成をProduction基準とする。

## Production budget

- `Suisui.app`: file payload合計50 MiB以下。`script/check_release_bundle_inventory.sh`が超過をfail closedにする。
- ZIP: 8 MiB以下。DMG: 9 MiB以下。`script/check_release_artifact_size.sh`が形式別に検証し、必要な変更は`SUISUI_MAX_ZIP_ARTIFACT_BYTES`または`SUISUI_MAX_DMG_ARTIFACT_BYTES`をPRで明示して更新する。
- 正式な多解像度アプリアイコンは1024pxキャンバスと全macOS表現を維持しつつ、視覚上十分な512px相当に最適化した。Developer ID署名、stapled ticket、Sparkle runtimeを含むproduction ZIP実測値8,059,051 bytesを根拠に上限を8 MiBとし、約322 KiBを超える追加回帰は拒否する。ZIP生成は`ditto --zlibCompressionLevel 9`を固定し、圧縮設定の揺れを容量回帰として誤検知しない。
- Release evidence: app bundle、main binary、ZIP/DMGの実測bytesとstrip/pruning modeを記録する。
- Review threshold: 新規依存または新規リソースがapp bundleを5 MiB以上増やす変更は、PRに代替案、ユーザー価値、更新・脆弱性対応責任を記載する。
- `.build`や開発者cacheの容量を、ユーザーへ配るapp bundleの容量として扱わない。

## Bundled and user-cache boundaries

- No bundled voice models. STT/TTSモデルは明示操作後にchecksum検証し、user cache (`Application Support/Suisui`)へ保存する。
- 大規模なAIモデル、生成cache、検証fixtureをapp bundleへ入れない。
- ネットワークがなくても、取得済みかつchecksum検証済みのモデルは利用できる設計を維持する。
- `script/check_release_bundle_inventory.sh`は配布appそのものを走査し、既知のモデル形式、`.DS_Store`、AppleDouble、dSYMの混入を拒否し、最大ファイルを表示する。

## Dependency decisions

### SwiftTerm

SwiftTermはDeveloper Modeの内蔵ターミナルという中核機能を成立させるため、現時点ではmain appに同梱する。別helperや別flavorに分割すると、インストール・更新・署名の複雑さが先に増えるためである。5 MiB review thresholdまたは50 MiB app budgetを超える場合は、helper分離を再評価する。

### Sparkle

Sparkleの`Resources`、`Updater.app`、`XPCServices`は更新ランタイムなので保持する。`Headers`、`PrivateHeaders`、`Modules`は実行時不要の開発資産なので、Release署名前にのみ削除する。Sparkleの翻訳リソースは`Base.lproj`とSuisui本体が実際に同梱するlocaleだけを保持し、アプリから選択不能な翻訳は署名前に削除する。削除後にnested codeを内側から署名し直し、署名・公証・更新smokeを実施する。

## Release workflow

1. Release buildを生成する。
2. `prepare_release_bundle.sh`でmain binaryをstripし、Sparkle開発資産を削除する。
3. `check_release_bundle_inventory.sh`で容量、最大ファイル、モデル非同梱を検証する。
4. nested codeを内側から署名し、appをDeveloper ID署名する。
5. appのnotarizationとstapleを行う。
6. `package_release.sh`でclean ZIP/DMGを生成し、配布DMG自体をnotarize/staple/Gatekeeper検証する。
7. DMG検証成功後にのみ、artifactのサイズ証跡とchecksumを保存する。

署名後のapp bundleはパッケージ生成時に変更しない。unsigned smokeでは`dist/Suisui.app`を一時ディレクトリへ複製し、そのコピーだけをstrip/pruneする。内容変更が必要になった場合は、Release buildの準備から署名・公証をやり直す。

ZIP/DMG生成後は、checksumとpackage evidenceの作成前にartifact容量を検証する。最終preflight、release evidence作成、appcast検証はpackage evidenceの容量値とstrip/pruning modeを実ファイルに照合し、旧形式や改変された証跡を拒否する。
