# 05 — Cold start degrades weight-guided batch sizing

Status: needs-triage

PR #12 (`scheduler/weight-guided-stealing`) で動的スケジューリングのバッチ幅が Weight 依存になった。その副作用として、Timing データがない状態 (cold start) での動的スケジューリングの質が、以前より Weight の質に強く結合している。ADR-0006 の Consequences に記録した含みを issue として切り出したもの。

## Problem

`Orchestrator#drain_batch` はバッチの切れ目を予測 Weight で決める:

```ruby
target = [queue.total_weight(@timings) / 2.0, MIN_BATCH_WEIGHT].max
```

`MIN_BATCH_WEIGHT` は 30.0、単位は「予測秒数」。ところが Timing ファイルにサンプルがないテストの Weight は `Timing#filesize_weight` が返すファイルサイズ (KB, 下限 1.0) で、単位が秒ではない。したがって cold start では:

- `MIN_BATCH_WEIGHT` の 30.0 が「30秒分の仕事」ではなく「合計 30KB 分のファイル」を意味してしまい、ランナー起動コストを償却するという本来の意図と対応しなくなる。
- ドナー選択 (`max_by { |q| q.total_weight(@timings) }`) も同じスケールで比較されるため、「残予測時間が最大のキュー」ではなく「残ファイルサイズが最大のキュー」を選ぶ。

壊れはせず、やや恣意的なバッチ幅に劣化するだけ (KB とテスト実行時間には弱い相関はある) だが、ADR-0002 が前提にしていなかった結合であり、静的 LPT のときは表面化しなかった。

## Impact

- calibrate 済みプロジェクトでは問題なし。実運用の主要経路はこちらなので、優先度は高くない。
- 影響を受けるのは (a) 初回導入直後で calibrate をスキップした場合、(b) CI キャッシュ miss かつコミット済み baseline なし (ADR-0005 の両層とも外れた場合)、(c) 新規追加されたテストが多数を占める場合。
- `binpacker-setup` は calibrate を通す前提なので、(a) は手順を踏めば回避される。

## Possible Directions

いずれも未検証。計測が先。

1. **cold start では動的バッチを使わない** — Timing が空なら `MIN_BATCH_WEIGHT` ベースの drain をやめ、固定件数バッチにフォールバックする。単位の混同が起きないのが利点だが、フォールバック経路が増える。
2. **filesize weight を秒にキャリブレートする** — 「KB あたり何秒」の係数を 1 回のランから推定して正規化する。単位が揃うので `MIN_BATCH_WEIGHT` の意味が保たれる。係数の推定精度が読めない。
3. **Weight の出所を型で持つ** — measured か推定かを Weight に持たせ、推定混じりのキューでは batch policy を切り替える。最も正確だが `Timing` / `WorkerQueue` の API に波及する。
4. **何もしない** — cold start は calibrate すべき、で押し切る。`binpacker describe` が未 calibrate を検出して警告する導線は既にある。この場合は ADR-0006 に「意図的に許容」と明記して閉じる。

## Acceptance Criteria

- cold start (Timing ファイルなし) の動的スケジューリングで、バッチ幅とドナー選択の意味が定義されている (単位が混ざったまま暗黙に動いている状態を解消する)。
- 上記 4 の「許容する」を選ぶ場合も、ADR-0006 と `docs/design/stealer-policy.md` にその判断が明記されていること。
- rigor の実 Weight を使ったシミュレーションで、cold start 時の makespan が固定件数バッチに対して劣化していないことを確認する。

## Comments

- 2026-07-15: PR #12 のドキュメント同期 (61fda7a) の過程で発見。実装バグではなく設計上の含みなので、コード変更は伴わず起票のみ。
