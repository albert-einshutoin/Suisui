# App Metadata

Suisui の public alpha は SwiftPM package から `.app` bundle を生成する。Xcode project に依存しないため、配布用 metadata は `packaging/app_metadata.env` を単一の設定ソースにする。

## Identity

- App name: `Suisui`
- Bundle identifier: `dev.suisui.app`
- App category: `public.app-category.productivity`
- Minimum macOS: `14.0`
- Marketing version: `0.1.0`
- Build number: `1`

## Versioning Rule

- `MARKETING_VERSION` は SemVer とし、ユーザーに見える alpha release ごとに更新する。
- `CURRENT_PROJECT_VERSION` は配布物を作るたびに単調増加させる整数にする。
- 同じ `MARKETING_VERSION` で再配布が必要な場合は、`CURRENT_PROJECT_VERSION` だけを上げる。
- release tag は `v<MARKETING_VERSION>-alpha.<CURRENT_PROJECT_VERSION>` 形式を使う。

## Entitlement Inventory

`packaging/Suisui.entitlements` は主アプリ実行ファイルに必要な権限だけを定義する。Apple の Hardened Runtime 方針に従い、機能に必要な entitlement だけを `true` で追加する。

現在要求する entitlement:

- Audio Input (`com.apple.security.device.audio-input = true`): 音声コマンドの録音と Core Audio の入力利用に必要。`NSMicrophoneUsageDescription` による利用目的表示と、macOS のユーザー許可は引き続き必要。

`script/sign_app.sh` はこの plist を `Suisui.app` の主アプリだけに適用する。Sparkle framework、Updater.app、Downloader XPCなどのnested codeは録音を行わないため、Hardened Runtime署名だけを付け、Audio Input entitlementを付与しない。これは権限を必要な実行ファイルに限定するための境界であり、nested codeが将来録音を必要とする設計へ変わらない限り維持する。

現在 entitlement として要求しないもの:

- App Sandbox: Mac App Store 配布ではないため、Developer ID alpha では有効化しない。
- Network client: BYOK LLM provider は通常の outbound HTTP で動くが、sandbox を有効化するまで entitlement は不要。
- File access: MVP はユーザーが選択した workspace 配下だけを扱い、sandbox scoped bookmark の設計は後続で検討する。
- Login item: `SMAppService` を使う。専用 entitlement は追加しない。

Entitlement を追加する場合は、該当 Phase のタスク、根拠、対象実行ファイル、検証コマンド、削除条件をこの文書に追記する。配布物では主アプリを `codesign -d --entitlements :- dist/Suisui.app` で確認し、nested codeに主アプリ用entitlementが混入していないことも確認する。

根拠:

- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Apple: Audio Input Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)
