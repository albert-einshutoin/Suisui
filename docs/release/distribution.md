# Distribution Packaging

SoloPM public alpha の標準配布物は `DMG` とする。Mac ユーザーが Finder 上で `SoloPM.app` を `Applications` に移せるように、DMG には `/Applications` への symlink を含める。

初回Productionリリースの対応環境はmacOS 14以降のApple Silicon（`arm64`）とする。Intel Macは対象外であり、配布ページとリリースノートにも同じ条件を明記する。`packaging/app_metadata.env`の`SUPPORTED_ARCHITECTURES`と実バイナリのsliceは、署名前に`script/verify_release_architecture.sh`で完全一致を検証する。Universal 2へ移行するときは、Intel環境の起動・更新・性能証跡を追加してから対応契約を変更する。

Sparkle appcast 用、またはapp bundleのnotarization submission用には ZIP も生成できるが、ユーザー向けの標準downloadはDMGに寄せる。ユーザーがdownloadする最外郭DMGも別途notary serviceへ送信し、ticketをstapleする。

容量上限、モデル非同梱、SwiftTerm/Sparkleの判断基準は [Package Size Policy](package-size-policy.md) を参照する。

## Build Package

署名済み、notarized、staple済みの`dist/Suisui.app`を作った後に実行する。通常実行では、作成したDMGを`notarytool submit --wait`へ送信し、DMG自体のstaple/validateとGatekeeper assessmentが成功した後でchecksumとpackage evidenceを確定する。

```bash
SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh
```

出力先は `dist/releases/`。

Production DMGの公証後には`*.dmg.notarization.json`も生成する。この非機密sidecarはnotary submission ID、`Accepted`状態、stapler/Gatekeeper結果、staple後DMGのSHA-256を保持し、最終preflightで配布DMGと再照合する。

```text
SoloPM-0.1.0+1.dmg
SoloPM-0.1.0+1.dmg.sha256
SoloPM-0.1.0+1.dmg.package-evidence.json
SoloPM-0.1.0+1.zip
SoloPM-0.1.0+1.zip.sha256
SoloPM-0.1.0+1.zip.package-evidence.json
```

ユーザー向け配布は DMG、Sparkle appcast は ZIP を参照する。release evidence は DMG checksum に明示的に紐づける。

```bash
source packaging/app_metadata.env
export SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"
```

署名環境がない開発機で packaging smoke だけ確認する場合は、明示的に署名要求を外す。

```bash
SOLOPM_REQUIRE_SIGNED_PACKAGE=0 \
SOLOPM_REQUIRE_NOTARIZED_PACKAGE=0 \
./script/package_release.sh
```

smoke modeは`dist/Suisui.app`を変更せず、一時コピーにだけrelease stripとSparkle開発資産のpruneを適用する。一時コピーは終了時に削除され、元bundleが署名済みでも署名を破壊しない。

release artifact を作る通常実行では、`SOLOPM_REQUIRE_SIGNED_PACKAGE=1` と `SOLOPM_REQUIRE_NOTARIZED_PACKAGE=1` が既定値になる。つまり `codesign --verify`、`xcrun stapler validate`、`spctl -a -vv` を通らない app bundle からは配布用 DMG / ZIP を作らない。

DMG工程は次の順序をfail-closedで固定する。

1. stapled appからDMGを作成する。
2. `notarytool submit <DMG> --wait`が`Accepted`を返すことを確認する。
3. DMGへ`stapler staple`し、`stapler validate`する。
4. `spctl -a -t open --context context:primary-signature`で配布コンテナを評価する。
5. 成功後にのみ容量gate、checksum、package evidenceを生成する。

ZIPはappへのstaple後に生成する。appのstaple前に作ったZIPを再利用するとticketを含まないため、必ず`notarize_app.sh`の後に`package_release.sh`で再生成する。

Developer ID署名前に`sign_app.sh`がmain binaryのlocal symbolをstripし、Sparkleの実行時不要なHeaders/Modulesを削除する。`package_release.sh`は署名・公証後のappを変更せず、AppleDoubleや不要な拡張属性を含めないclean ZIPを生成する。package evidenceにはapp、main binary、artifactのbytesとstrip/pruning modeが記録される。

署名必須の通常実行では、署名前準備markerがない旧バンドルや、strip/pruningが無効なバンドルを拒否する。外部ツールで署名だけを付けたappを再利用せず、`./script/sign_app.sh`から作り直す。

上記の smoke mode は `dist/package-smoke/` に出力し、`dist/releases/` には置かない。`packaging/release-evidence.json` は `dist/releases/*.package-evidence.json` で signed / notarized gate が有効だったことを確認するため、smoke artifact は release evidence として使えない。

## Checksum

各 artifact には `shasum -a 256` の checksum を出す。GitHub Release や release notes には artifact 名と checksum を併記する。

## Manual Check

clean 環境で以下を確認する。

1. DMG を download する。
2. checksum が release notes と一致する。
3. DMG を開き、`SoloPM.app` と `Applications` symlink が見える。
4. `SoloPM.app` を Applications に移動する。
5. 初回起動時に Gatekeeper で拒否されない。
