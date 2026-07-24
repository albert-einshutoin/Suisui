# Privacy / Security

Suisui public alpha is local-first. The app is designed so users can inspect the plan before write actions run.

## Local Data

- Projects, tasks, Knowledge Frames, deadlines, and audit logs are local.
- API Key values are stored in Keychain.
- Release credentials, Developer ID certificates, notary credentials, and Sparkle private keys stay in Keychain or a CI secret store.
- Local logs must redact API keys, bearer tokens, authorization headers, passwords, and secret-like values.

## LLM 送信文脈

LLM 送信文脈 is limited to the text needed to generate an Action Plan. The app should keep the generated plan visible before execution, and write actions require approval.

Codex Localでは、ユーザーが指定して明示承認したローカル`codex` executableを短時間起動し、ChatGPTログインと利用枠の管理をCodex App Serverへ委譲する。通常モードはOpenAI Team ID `2DC432GLL2`、signing identifier `codex`の有効なmacOS署名を要求する。Developer Modeでは未署名・カスタムbuildを明示承認できるが、Developer Modeを無効にすると承認も失効する。承認はresolved path、device/inode/mtime/sizeに加え、streaming SHA-256、signing identifier、Team ID、designated requirementへ結び付けられ、`--version`とApp Server起動の直前に再検証される。package manager更新やsymlink差し替えを含む不一致は再承認までfail closedとなる。Suisuiは`~/.codex/auth.json`、access token、refresh tokenを読み取らない。画面には接続状態と契約種別を表示できるが、account emailは永続化しない。

## 送信しない

- Raw Keychain secrets
- Developer ID certificate material
- Sparkle private update keys
- Full local folder contents without explicit user approval
- Hidden files or private project files unrelated to the user request
- Codex credential store、ChatGPT token、account emailを含むdiagnostics / sync payload / execution receipt

## 削除しない

- Local files
- Calendar events
- Reminders
- Knowledge Frames
- Audit logs

The public alpha does not include destructive delete tools.

## 自動投稿しない

- Email send
- Slack post
- Git push
- GitHub issue or PR mutation
- External SaaS write actions

The MVP may create drafts or local plans only after review.

## Codex Local release verification

- 通常テストではfixtureにcredential fieldがなく、production login型からtoken注入を表現できないことを確認する。
- Stableの署名policyはOpenAI Team ID `2DC432GLL2`とsigning identifier `codex`を固定し、verified version allowlistとは独立して両方を満たすことを確認する。SHA-256または署名identityの不一致時はcredentialやpromptを送る前に停止し、更新されたexecutableは再承認する。
- opt-inの`script/check_codex_app_server_smoke.sh`は、現在のmacOSユーザー自身のCodex利用枠を消費し得るため、明示的な環境変数がある場合だけ実行する。
- smokeは最低version、ログイン状態、toolを無効化したAction Plan生成を確認し、標準出力へtokenやaccount emailを出さない。
- Enterprise対応は`clientInfo.name = "suisui"`のknown-client登録、またはCompliance Logs上の制約を公開文書へ明記するまで対象外とする。
- `script/check_codex_auth_access_evidence.sh`は、macOSで単一の短時間`ktrace`を取得し、同じraw traceを`fs_usage -R`でsystem・Suisui parent・Codex childの各視点から再生する。Swift監査経路はparent PIDを公開した直後に待機し、`ktrace`の開始通知を確認してからtransport・account client・App Server processを含むCodex production経路を開始する。privileged helperとのready/stop channelは呼び出し元が空の`0600`通常ファイルとして事前作成し、helperはowner UID/GID・mode・空サイズ・非symlinkを検証してから使用する。実監査前には専用sentinelでcapture windowと終了済みPIDの分類を校正し、Suisui parentが0件、Codex childが1件以上、未知PIDが0件である場合だけ証跡を公開する。全filesystem eventを含み得るraw traceは権限を`0600`に制限した一時領域だけに置き、成功・失敗を問わず削除する。追跡可能な証拠にはpath class、件数、capture backend、macOS build、product source commit、audit harness commit、検証済みCodex versionだけを残す。

## Telemetry

Crash reporting and telemetry are not enabled by default. If telemetry is added later, it must be opt-in and documented before release.
