# Phase 5: Packaging

目的は、Suisui を最初の public alpha として配布できる品質に整えること。機能追加ではなく、署名、notarization、自動更新、ライセンス、プライバシー、リリース手順を固める。

## Scope

- Developer ID signing
- Notarization
- DMG / ZIP distribution
- Sparkle update
- Founder license
- First public alpha
- OSS としての公開準備

## Non-goals

- Mac App Store 配布
- Cloud sync
- Team plan
- SaaS connector の本実装
- 課金サーバーの大規模構築

## Checklist

### P5-001: App identity and bundle configuration

- [x] bundle identifier、app category、versioning rule を決める。
- [x] `CFBundleShortVersionString` と build number の更新ルールを作る。
- [x] entitlement を棚卸しし、不要な権限を入れない。
- [x] テスト: Debug / Release build の bundle 設定差分を確認する。
- [x] 完了条件: 配布物として識別可能な app metadata がある。

### P5-002: Developer ID signing

- [x] Developer ID Application certificate を使う signing 設定を作る。
- [x] CI で signing するか、local release machine で signing するか決める。
- [x] secret は Keychain / CI secret に保存し、repo に入れない。
- [ ] 手動確認: signed app を `codesign --verify` で確認する。
- [ ] 完了条件: Gatekeeper で拒否されない署名済み app を作れる。

### P5-003: Notarization pipeline

- [x] `xcrun notarytool` を使った notarization 手順を scripts または docs にする。
- [x] staple 手順を含める。
- [x] notarization 失敗時の log 取得手順を書く。
- [ ] 手動確認: notarized app を別ユーザー環境で起動確認する。
- [x] 完了条件: release checklist に沿って notarization できる。

### P5-004: DMG / ZIP packaging

- [x] DMG と ZIP のどちらを alpha 標準にするか決める。
- [x] DMG を使う場合は Applications への導線を作る。
- [x] checksum を出す。
- [ ] 手動確認: clean 環境で download、展開、起動できる。
- [x] 完了条件: ユーザーが迷わずインストールできる。

### P5-005: Sparkle update foundation

- [x] Sparkle を導入する。
- [x] appcast feed の生成手順を作る。
- [x] update signing key を安全に保管する。
- [x] テスト: local appcast で update check smoke を行う。
- [x] 完了条件: alpha 以降の更新を手動再配布だけに依存しない。

### P5-006: Founder license / local entitlement

- [x] Founder / Personal Plus などの license model を local-first で扱う最小仕様を決める。
- [x] MVP は購入処理を入れず、license file / code の検証 skeleton に留めるか判断する。
- [x] ライセンス情報に個人情報を過剰に含めない。
- [x] テスト: valid、expired、missing license の表示 state を確認する。
- [x] 完了条件: 将来の課金導線を壊さない最小境界がある。

### P5-007: Privacy and security docs

- [x] API Key は Keychain、操作ログは local、LLM 送信文脈は確認可能という方針を書く。
- [x] MVP で送信しないもの、削除しないもの、自動投稿しないものを明記する。
- [x] Crash / telemetry を入れる場合は opt-in にする。入れない場合も明記する。
- [x] 完了条件: OSS としてユーザーが安全性を評価できる。

### P5-008: OSS project documents hardening

- [x] Phase 0 で作成した root `README.md` を public alpha 向けに更新し、スクリーンショット、MVP scope、known limitations を追加する。
- [x] `LICENSE` を追加または最終確認する。
- [x] `CONTRIBUTING.md` に alpha 期の issue triage、review policy、supported environment を追記する。
- [x] `SECURITY.md` に脆弱性報告先、対象バージョン、secret handling 方針を最終化する。
- [x] 完了条件: 外部 contributor と alpha user が参加、検証、報告できる情報がある。

### P5-009: Release checklist

- [x] test、build、sign、notarize、package、checksum、appcast、tag、release notes の順序を書く。
- [x] rollback 手順を書く。
- [x] known issues を release notes に含める。
- [x] 手動確認: checklist だけを見て alpha build を再現できる。
- [x] 完了条件: release 作業が属人化していない。

### P5-010: First public alpha

- [x] alpha scope を Phase 0-4 の完了範囲に限定する。
- [x] known limitations に外部 MCP、SaaS、RAG、Team 未対応を明記する。
- [x] sample workflow を 3 つ用意する。
- [x] alpha feedback の受付先を用意する。
- [x] 完了条件: OSS として触って価値が分かる alpha が出せる。

## Exit Gate

- [ ] signed / notarized build を作れる。
- [x] Sparkle update の smoke が通る。
- [x] privacy / security / contributing docs がある。
- [x] release checklist で alpha を再現できる。
- [x] MVP 外の危険機能を混ぜていない。

残タスク: 未チェック項目は Developer ID Application certificate、Apple notary profile、clean/別ユーザー環境が必要な release gate。scripts/docs と `packaging/release-evidence.example.json` は実装済みだが、この開発環境だけでは完了判定しない。
