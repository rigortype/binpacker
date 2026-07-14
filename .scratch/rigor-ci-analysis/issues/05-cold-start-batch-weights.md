# 05 — Cold start degrades weight-guided batch sizing

Status: resolved

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
- 2026-07-15: 採用した方向性は Possible Directions の 2+1 のハイブリッド。(2) `Timing#load_with_fallback` が計測済みファイルから「KB あたり何秒」の係数 (測定済みかつディスク上に存在するファイルの `measured_seconds / size_kb` の中央値) を推定し、未計測ファイルの filesize weight をこの係数でスケールする (下限 0.01)。係数が推定できない場合 (サンプルが1件もない、または測定済みファイルが1つもディスク上に存在しない) は生の KB のまま (下限 1.0) で、内部的な相対比較としては一貫している。これにより calibrate 済みかつ新規テストが混在するようなケースでも単位が揃う。(1) の「固定件数バッチにフォールバック」そのものではなく、pure cold start (samples が空、= `Timing#calibrated?` が false) のときだけ `Orchestrator` 側で `MIN_BATCH_WEIGHT` を読まず、スケールフリーな下限 (`total_predicted_weight / (worker_count * COLD_START_BATCHES_PER_WORKER)`, `COLD_START_BATCHES_PER_WORKER = 5`) を使う、という専用の分岐にした。合計 Weight やワーカー数が 0 のときは従来通り `MIN_BATCH_WEIGHT` にフォールバックする。

  検証は Monte Carlo シミュレーション (200+ trials/config, 312 files / 4 workers / 3s boot / execution-noise CV 0.13, filesize をノイズ入りの duration predictor として使用)。要点:
  - rigor 実スケール相当 (spec 合計 ~900KB) では旧固定 30 floor と新スケールフリー floor は統計的に区別できなかった。30-as-KB が偶然 `total / 20` 付近に収まっていたため。
  - 意外だったのは、旧実装の実際の failure mode が「無駄に細かいバッチ」ではなく逆方向だったこと: 小規模コードベース (合計 ~57KB) では floor=30KB がワーカー1人分のキュー全体を上回ってしまい、dynamic mode が実質「ワーカーごとに boot 1回」= バッチ分割と steal が事実上無効化された静的スケジューリングに縮退し、最大偏差 9.2% だった。スケールフリー floor は同じスケールでも ~2.7 boots/worker を保ち、偏差 7.4%。
  - `COLD_START_BATCHES_PER_WORKER` 自体は鈍感な定数: 3→8 で振っても boots/worker は ~2.6→2.8 とほぼ動かない。drain ルールが半減を繰り返すため log2 ステップ程度で floor に収束するのが理由。5 のままで妥当、過剰にチューニングする価値はない。
  - cold start 系のポリシーはいずれも最大偏差 5-9% 程度で、calibrate 済みオラクル (~2.3-2.4%) には及ばない。predictor のノイズ (KB vs 真の秒数) が支配的要因であり、今回の変更は単位の不整合と小規模コードベースでの劣化を解消するだけで、cold start 自体の予測精度を上げるものではない。calibrate が本質的な解決策であることに変わりはない。

  Acceptance Criteria の状況: 単位の定義 (Batch 幅とドナー選択の意味) — 完了。固定件数バッチに対して cold start 時の makespan が劣化していないことのシミュレーション確認 — 完了、fixed-10 は今回試した中で makespan が最悪かつ ~8 boots/worker だった。
