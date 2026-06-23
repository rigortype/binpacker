# Rigor CI 実測データ分析 — 改善余地

Status: needs-triage

## Source

rigortype/rigor PR [#29 Bump binpacker to 0.2.0](https://github.com/rigortype/rigor/pull/29) CI run 28034424567 の全ジョブ実測値を分析。

## サマリ

PRのCI所要時間: ~10分強 (ジョブ合計、並列度を考慮しない単純和)

| Job | Duration | Description |
|-----|----------|-------------|
| Tests (Ruby 4.0) | 6m36s | binpacker 4 workers, 290 files, 7019 examples |
| Self-check (cold) | 1m51s | rigor check lib (17.47s) + coverage (16s) + plugins (5s) + incremental (55s) |
| Self-check (warm) | 29s | キャッシュミスにより実質cold (16.41s) |
| RBS compat (4.x) | 47s | RBS 4.x compatibility specs |
| RBS compat (3.x) | 43s | RBS 3.x compatibility specs |
| Lint | 13s | RuboCop |
| Self-check diff | 6s | warm == cold 一致確認 (自明: 両方cold) |
| CI required | 2s | Fan-in gate |

## Tests (Ruby 4.0) ワーカー分布

```
W0: 70 files, 5m54.5s | 1703 examples  ← 最遅
W1: 72 files, 5m29.4s | 1890 examples
W2: 74 files, 5m19.3s | 1565 examples  ← 最速
W3: 74 files, 5m29.8s | 1861 examples
Total: 290 files, 22m13.1s | 7019 examples
Balance: max deviation 21.3s (6.4%)
```

- タイミングキャッシュ: **HIT** (前回run 27977327407より復元)
- LPT最適解(333s×4)から21.3s乖離
- Per-file runtime: W0 5.06s/file vs W2 4.31s/file (17.4%のばらつき)

## Self-check キャッシュ分析

| Variant | Wall time | Memory | Cache restore |
|---------|-----------|--------|--------------|
| cold | 17.47s | 286.0 MB | — |
| warm | 16.41s | 278.1 MB | **MISS** — no existing key |

warmのキャッシュキー:
```
rigor-cache-<OS>-<Gemfile.lock hash>-<lib/sig/builtins hash>
```

このPRでGemfile.lockが変更されたため、キャッシュキー不一致によりmiss。restore-keysも該当なし。

### インクリメンタル検証の実測値

```
lib:         157/313 files re-analyzed (50.2% from cache) — 41s
plugins:      71/141 files re-analyzed (50.4% from cache) — 14s
```

### 精度カバレッジ

```
expressions typed: 121,249
precise:           68,051 (56.1%)  ← threshold 43%に対し+13.12pt
dynamic opaque:    53,198 (43.9%)

Tier breakdown:
  constant     33,810 (27.9%)
  nominal      25,824 (21.3%)
  shaped        4,686 (3.9%)
  refined          98 (0.1%)
  bot           3,633 (3.0%)
  dynamic      53,198 (43.9%)
```

### ワースト精度ファイル

| File | Precision | Dynamic count |
|------|-----------|--------------|
| incremental_session.rb | 30.5% | ~470 |
| type_scan_renderer.rb | 34.3% | ~322 |
| fused_protection_renderer.rb | 34.4% | ~122 |
| incremental.rb | 34.8% | ~174 |
| synthetic_method_scanner.rb | 37.9% | ~921 |
| sig_gen/writer.rb | 40.4% | ~756 |
| trace_renderer.rb | 44.6% | ~524 |
| conformance_checker.rb | 39.8% | ~397 |

### 診断

- rbs.coverage.missing-gem: 32 gem(s) in Gemfile.lock have no RBS available

## 転記すべき主要Issue

1. **binpacker LPTバランス改善** — 21.3s(6.4%)の偏在、タイミングデータありでも不十分
2. **Warm jobキャッシュ最適化** — 依存bump PRでwarm jobが常にcache miss、無駄
3. **Precision threshold引き上げ** — 現状43%は実測56%に対して余裕が大きすぎる
4. **binpacker進捗ログ anomaly** — 358s時点でW0 done / 他worker 0/N と表示される不具合

## 関連Issue一覧

| # | Slug | Priority | Status |
|---|------|----------|--------|
| 01 | lpt-balance | High | needs-triage |
| 02 | cache-miss-optimization | High | needs-triage |
| 03 | precision-improvement | Medium | needs-triage |
| 04 | progress-logging | Low | needs-triage |
