# Phase 8: SaaS Connectors

目的は、Suisui の local-first 体験を保ちながら、必要な外部 SaaS へ draft / approval-first で接続すること。OAuth scope、token storage、write confirmation を厳格に扱う。

## Scope

- Google Calendar
- Gmail Draft
- Slack Draft / Post with approval
- Google Drive
- Notion
- OAuth / token lifecycle

## Non-goals

- メール自動送信
- Slack 自動投稿
- 全 Drive / Notion の無許可 scan
- Team admin features
- Cloud sync

## Checklist

### P8-001: OAuth foundation

- [x] OAuth provider abstraction を作る。
- [x] token は Keychain に保存する。
- [x] scope は connector ごとに最小化する。
- [x] refresh、revocation、disconnect を実装する。
- [x] テスト: token refresh success / failure、disconnect、scope mismatch を確認する。
- [x] 完了条件: どの connector でも token handling が重複しない。

### P8-002: Google Calendar connector

- [x] Apple Calendar と同じ `calendar.create_event` abstraction に接続する。
- [x] Google Calendar 固有の calendar id、timezone、all-day event を扱う。
- [x] write は Review UI approval 必須にする。
- [x] テスト: Google client test double で create、permission denied、invalid calendar を確認する。
- [x] 完了条件: Apple / Google の差分が UI に漏れすぎない。

### P8-003: Gmail Draft connector

- [x] Gmail は draft 作成までに限定する。
- [x] send scope は要求しない。
- [x] 宛先、件名、本文、添付なし / あり方針を Review UI で確認する。
- [x] テスト: send action が存在しないこと、draft create approval が必要なことを確認する。
- [x] 完了条件: メール送信事故が起きない設計になっている。

### P8-004: Slack connector

- [x] 最初は Slack message draft を作る。
- [x] post は explicit approval がある場合のみ対応する。
- [x] channel list 読み取り scope と post scope を分ける。
- [x] テスト: approval なし post 拒否、channel missing、token revoked を確認する。
- [x] 完了条件: Slack 連携が通知下書き補助として安全に使える。

### P8-005: Google Drive connector

- [x] Drive は file picker / selected folder を基本にする。
- [x] 全 Drive scan はしない。
- [x] docs / sheets / slides の作成は draft / write approval を通す。
- [x] テスト: selected folder 以外の write が拒否されることを確認する。
- [x] 完了条件: ユーザーが選択した範囲だけ扱う。

### P8-006: Notion connector

- [x] Notion database / page の接続先をユーザーが選択する。
- [x] task / project の write mapping を設定 UI で確認できるようにする。
- [x] 自動同期ではなく明示的な export / create から始める。
- [x] テスト: mapping missing、approval missing、API failure を確認する。
- [x] 完了条件: Notion 側の構造差分を Suisui core に漏らさない。

### P8-007: Connector health dashboard

- [x] 各 connector の connected / disconnected / token expired / permission issue を表示する。
- [x] test connection を実行できる。
- [x] last success / last error を audit log から表示する。
- [x] テスト: token expired 表示と reconnect 導線を確認する。
- [x] 完了条件: 外部連携の故障原因をユーザーが理解できる。

## Exit Gate

- [x] OAuth token は Keychain 管理。
- [x] write / post / draft create は approval 必須。
- [x] Gmail send と Slack auto-post は実装していない。
- [x] connector ごとに `Tests/` 配下の test double coverage がある。
- [x] disconnect と token revocation を扱える。

## Implementation Notes

- Production connector protocols live in `Sources/SuisuiExternalConnectors/SaaSConnectors.swift`.
- テスト: `Tests/SuisuiCoreTests/SaaSConnectorTests.swift`
- Test doubles live under `Tests/SuisuiCoreTests/SaaSConnectorTests.swift` and are only linked through the test target.
- OAuth token の secret material は `SecretStore` 経由で保存し、metadata には `SecretKey` reference、scope、expiry のみを保持する。
- Google Calendar / Gmail / Slack / Google Drive / Notion は `SuisuiExternalConnectors` target の production protocol / connector boundary として実装し、本番 API adapter は Phase8 foundation の外側で差し替える。
- Public alpha の `Suisui` app / `suisui-cli` は `SuisuiExternalConnectors` に依存せず、外部 SaaS 連携を runtime から除外する。
- Gmail は draft create のみを公開し、send scope / send operation は持たない。
- Slack は draft と post を分け、post は explicit approval 必須にする。自動投稿は実装していない。
- Drive は selected folder id 以外への write を拒否する。
- Notion は mapping が無い project / task write を拒否する。
- health dashboard は disconnected / token expired / permission issue / last audit error を表示できる snapshot を返す。

## Verification

- `swift test --filter SaaSConnectorTests`

## Links

- ADR: `docs/adr/0006-optional-connectors-and-knowledge-boundaries.md`
