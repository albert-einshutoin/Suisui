# Phase 8: SaaS Connectors

目的は、SoloPM の local-first 体験を保ちながら、必要な外部 SaaS へ draft / approval-first で接続すること。OAuth scope、token storage、write confirmation を厳格に扱う。

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

- [ ] OAuth provider abstraction を作る。
- [ ] token は Keychain に保存する。
- [ ] scope は connector ごとに最小化する。
- [ ] refresh、revocation、disconnect を実装する。
- [ ] テスト: token refresh success / failure、disconnect、scope mismatch を確認する。
- [ ] 完了条件: どの connector でも token handling が重複しない。

### P8-002: Google Calendar connector

- [ ] Apple Calendar と同じ `calendar.create_event` abstraction に接続する。
- [ ] Google Calendar 固有の calendar id、timezone、all-day event を扱う。
- [ ] write は Review UI approval 必須にする。
- [ ] テスト: fake Google client で create、permission denied、invalid calendar を確認する。
- [ ] 完了条件: Apple / Google の差分が UI に漏れすぎない。

### P8-003: Gmail Draft connector

- [ ] Gmail は draft 作成までに限定する。
- [ ] send scope は要求しない。
- [ ] 宛先、件名、本文、添付なし / あり方針を Review UI で確認する。
- [ ] テスト: send action が存在しないこと、draft create approval が必要なことを確認する。
- [ ] 完了条件: メール送信事故が起きない設計になっている。

### P8-004: Slack connector

- [ ] 最初は Slack message draft を作る。
- [ ] post は explicit approval がある場合のみ対応する。
- [ ] channel list 読み取り scope と post scope を分ける。
- [ ] テスト: approval なし post 拒否、channel missing、token revoked を確認する。
- [ ] 完了条件: Slack 連携が通知下書き補助として安全に使える。

### P8-005: Google Drive connector

- [ ] Drive は file picker / selected folder を基本にする。
- [ ] 全 Drive scan はしない。
- [ ] docs / sheets / slides の作成は draft / write approval を通す。
- [ ] テスト: selected folder 以外の write が拒否されることを確認する。
- [ ] 完了条件: ユーザーが選択した範囲だけ扱う。

### P8-006: Notion connector

- [ ] Notion database / page の接続先をユーザーが選択する。
- [ ] task / project の write mapping を設定 UI で確認できるようにする。
- [ ] 自動同期ではなく明示的な export / create から始める。
- [ ] テスト: mapping missing、approval missing、API failure を確認する。
- [ ] 完了条件: Notion 側の構造差分を SoloPM core に漏らさない。

### P8-007: Connector health dashboard

- [ ] 各 connector の connected / disconnected / token expired / permission issue を表示する。
- [ ] test connection を実行できる。
- [ ] last success / last error を audit log から表示する。
- [ ] テスト: token expired 表示と reconnect 導線を確認する。
- [ ] 完了条件: 外部連携の故障原因をユーザーが理解できる。

## Exit Gate

- [ ] OAuth token は Keychain 管理。
- [ ] write / post / draft create は approval 必須。
- [ ] Gmail send と Slack auto-post は実装していない。
- [ ] connector ごとに fake client test がある。
- [ ] disconnect と token revocation を扱える。
