# Sparkle Updates

SoloPM は public alpha 以降の更新を手動再配布だけに依存しないため、Sparkle 2 を update foundation として導入する。

## Dependency

Sparkle は SwiftPM dependency として `SoloPM` app target に追加する。`script/build_and_run.sh` は SwiftPM build output の `.framework` を `SoloPM.app/Contents/Frameworks` にコピーし、配布 signing では nested framework も署名する。

## Feed And Public Key

Sparkle の feed URL と public EdDSA key は release build 時だけ Info.plist に入れる。
`SOLOPM_SPARKLE_FEED_URL` は production HTTPS appcast URL を environment か `packaging/sparkle.env` に設定する。release build は未設定、非 HTTPS、予約ドメイン、ローカルドメインを拒否する。

```bash
SOLOPM_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only
```

private update key は Sparkle の `generate_keys` tool で Keychain に保存し、repo に入れない。

```bash
generate_keys
```

## Appcast Generation

release artifact を `dist/releases/` に作った後、Sparkle の `generate_appcast` tool で appcast を生成する。

```bash
SOLOPM_SPARKLE_BIN_DIR=/path/to/Sparkle/bin ./script/generate_appcast.sh
```

Sparkle tools が SwiftPM artifact 配下にある場合、`script/generate_appcast.sh` は `.build/artifacts/.../Sparkle/bin` も探す。

## Local Appcast Smoke

署名 key がない開発機でも、local appcast の XML と version metadata は smoke できる。

```bash
./script/verify_appcast.sh
```

release appcast は generated `dist/releases/appcast.xml` を対象にし、sample placeholder signature や example URL が残っていないことを確認する。`SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX` は environment か `packaging/sparkle.env` に production HTTPS artifact URL prefix を設定する。

```bash
SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/generate_appcast.sh
SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml
```

本物の update check smoke は、Developer ID signed / notarized の古い app と、新しい appcast artifact が揃った状態で行う。Sparkle の private key、Developer ID certificate、notary profile が必要になる。
