# Sparkle Updates

Suisui は public alpha 以降の更新を手動再配布だけに依存しないため、Sparkle 2 を update foundation として導入する。

## Dependency

Sparkle は SwiftPM dependency として `Suisui` app target に追加する。`script/build_and_run.sh` は SwiftPM build output の `.framework` を `Suisui.app/Contents/Frameworks` にコピーし、配布 signing では nested framework も署名する。

## Feed And Public Key

Sparkle の feed URL と public EdDSA key は release build 時だけ Info.plist に入れる。
`SUISUI_SPARKLE_FEED_URL` は production HTTPS appcast URL を environment か `packaging/sparkle.env` に設定する。`SUISUI_SPARKLE_PUBLIC_ED_KEY` は Sparkle `generate_keys` の public EdDSA key を設定する。release build は未設定、非 HTTPS、予約ドメイン、ローカルドメイン、placeholder key、base64 形状でない public key を拒否する。
final preflight は signed app の `SUFeedURL` / `SUPublicEDKey` が現在の release config と一致することも確認する。feed URL や public key を変更した場合は、署名・notarization の前に app bundle を作り直す。

```bash
SUISUI_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only
```

private update key は Sparkle の `generate_keys` tool で Keychain に保存し、repo に入れない。複数organizationを扱うrelease machineではorganization固有のaccount名を指定し、同じ値をlocal-onlyの`SUISUI_SPARKLE_ACCOUNT`へ設定する。

```bash
generate_keys --account albert-einshutoin
```

## Appcast Generation

release artifact を `dist/releases/` に作った後、Sparkle の `generate_appcast` tool で appcast を生成する。

```bash
SUISUI_SPARKLE_BIN_DIR=/path/to/Sparkle/bin ./script/generate_appcast.sh
```

Sparkle tools が SwiftPM artifact 配下にある場合、`script/generate_appcast.sh` は `.build/artifacts/.../Sparkle/bin` も探す。

## Local Appcast Smoke

署名 key がない開発機でも、local appcast の XML と version metadata は smoke できる。

```bash
./script/verify_appcast.sh
```

release appcast は generated `dist/releases/appcast.xml` を対象にし、sample placeholder signature や example URL が残っていないことを確認する。`SUISUI_SPARKLE_DOWNLOAD_URL_PREFIX` は environment か `packaging/sparkle.env` に production HTTPS artifact URL prefix を設定する。release appcast verification は appcast が指す ZIP artifact、`.sha256`、`.package-evidence.json` も同じ release directory から検証する。

最終オンラインpreflightでは、Sparkleの`sign_update --verify`でZIPのEdDSA署名を暗号学的に検証し、本番feedとenclosureをHTTPSで取得して、公開ZIPのSHA-256がローカルの確定artifactと一致することも確認する。単に`edSignature`属性が存在するだけではProduction証跡として扱わない。

```bash
SUISUI_REQUIRE_RELEASE_APPCAST=1 ./script/generate_appcast.sh
SUISUI_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml
```

本物の update check smoke は、Developer ID signed / notarized の古い app と、新しい appcast artifact が揃った状態で行う。Sparkle の private key、Developer ID certificate、notary profile が必要になる。
