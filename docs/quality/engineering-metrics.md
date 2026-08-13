# Engineering metrics baseline

`script/quality_metrics_baseline.py` は、`.github/workflows/ci.yml` の `ci.yml` workflow を対象に、直近の有限個のGitHub Actions runを再計測するための標準ライブラリのみの集計器です。`ci/run-full.sh` が出すローカル実行証跡とは別に、ホスト側の再実行・完了結果を比較できます。

```sh
python3 script/quality_metrics_baseline.py \
  --repository albert-einshutoin/Suisui \
  --workflow ci.yml --branch main --limit 100 \
  --output docs/quality/engineering-metrics-baseline.json
```

`gh api` はGETだけを使います。各論理runは `id` ごとに1件で、最大attemptを最終結果とします。`run_attempt > 1` のrunだけ初回attemptを追加取得するため、`--limit` は最終runの上限（1--100）です。

## Schema v1

- `runs.total` は論理run数、`completed` は最終statusが `completed` の数です。
- `success`、`failure`、`cancelled`、`neutral` は既知の最終conclusionの分類です。`failure` は `failure` / `action_required` / `timed_out`、`cancelled` は `cancelled` / `stale`、`neutral` は `neutral` / `skipped` を含みます。
- `firstAttemptSuccessRate` は結論が取得できた初回attemptだけを分母にします。`rerunRate` は再実行された論理runの割合、`overallSuccessRate` は結論が既知の完了した最終runだけを分母にします。`averageAttempts` は論理runごとの最終 `run_attempt` の平均です。
- 値が算出不能なら数値の `0` ではなく `null` と `<metric>Status: "unavailable"` を出します。一部だけ算出できる率は `"partial"` を明示します。初回attemptまたは最終conclusionが一部欠けるサンプルは `sampleStatus: "partial"`、runがなければ `"empty"` です。

同一入力は、キー順序を固定した同一のJSONになります。意図的に取得時刻や利用者情報は含めません。保存済みのbaselineは取得時点の比較用スナップショットであり、継続的な成功率の主張ではありません。

## Fixture verification

ネットワークなしでは `--stdin` に `gh api` の `workflow_runs` JSONを渡します。

```sh
python3 script/quality_metrics_baseline.py --stdin --repository owner/repo < fixture.json
python3 -m unittest ci.tests.test_quality_metrics_baseline
```
