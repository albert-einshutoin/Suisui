# Notarization

SoloPM の notarization は local release machine で行う。Apple ID、app-specific password、API key などの credentials は repo に保存せず、`xcrun notarytool store-credentials` で Keychain profile として保存する。

## Setup

```bash
xcrun notarytool store-credentials SoloPMNotaryProfile
```

`packaging/notarization.env.example` を参考に、ローカルだけで `packaging/notarization.env` を作る。

```bash
SOLOPM_NOTARY_PROFILE=SoloPMNotaryProfile
SOLOPM_REQUIRE_NOTARIZATION=1
```

## Flow

```bash
./script/sign_app.sh
./script/notarize_app.sh
```

`script/notarize_app.sh` は `dist/Suisui.app` を ZIP 化し、`xcrun notarytool submit --wait` で notarization を待つ。成功後に `xcrun stapler staple` と `xcrun stapler validate` を実行し、最後に `spctl -a -vv` で Gatekeeper の trust policy を確認する。

## Failure Log

notarization が失敗した場合は、submission id を使って詳細 log を取得する。

```bash
xcrun notarytool log <submission-id> --keychain-profile SoloPMNotaryProfile
```

`script/notarize_app.sh` は submit output を `dist/notary/notarytool-submit.log` に残す。credential 不足、unsigned binary、hardened runtime 不足、nested code の署名不備をまず切り分ける。

## Manual Check

staple 済み app は、別ユーザーまたは clean 環境でダウンロード、展開、初回起動を確認する。現時点の開発機で Developer ID Application identity と notary profile が未設定の場合、この手動確認は実施できない。
