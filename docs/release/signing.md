# Developer ID Signing

SoloPM の public alpha は、当面 `local release machine` で Developer ID signing を行う。CI signing は、CI secret store と release 権限の設計が固まるまで延期する。

## Secret Boundary

- Developer ID Application certificate と private material は macOS Keychain に保存する。
- CI signing を導入する場合も、secret は CI provider の secret store に保存する。
- `packaging/signing.env` はローカル専用で、repo に入れない。
- `packaging/signing.env.example` には identity 名だけを置き、証明書、認証情報、notarization credential は置かない。

## Local Setup

1. Developer ID Application certificate をインストールする。
2. 利用できる identity を確認する。

```bash
security find-identity -p codesigning -v
```

3. `packaging/signing.env.example` を参考に、ローカルだけで `packaging/signing.env` を作る。

```bash
SOLOPM_SIGNING_IDENTITY="Developer ID Application: Example Name (TEAMID)"
SOLOPM_REQUIRE_SIGNING=1
```

## Signing

```bash
./script/verify_signing_setup.sh
./script/sign_app.sh
```

`script/sign_app.sh` は既定で release configuration の app bundle を作り直してから signing する。既存 bundle を明示的に署名したい場合だけ、`SOLOPM_SIGNING_SKIP_BUILD=1` を指定する。

## Validation

```bash
codesign --verify --strict --deep --verbose=2 dist/SoloPM.app
codesign -dvvv --entitlements :- dist/SoloPM.app
spctl -a -vv dist/SoloPM.app
```

`codesign --verify` は署名の整合性を確認する。`spctl -a -vv` は Gatekeeper の trust policy を確認する。notarization は別タスクで扱うため、この手順では staple 済み判定までは要求しない。

## Current Limitation

Developer ID Application identity が入っていない環境では `script/sign_app.sh` は失敗する。これは release signing を ad hoc signing に落とさないための意図した挙動。
