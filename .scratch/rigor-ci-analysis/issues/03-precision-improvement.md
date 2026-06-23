# 03 — Raise precision coverage threshold and target worst files

Status: needs-triage

**Note:** このIssueは主に rigortype/rigor リポジトリの自己分析 (Self-check) に関するもの。binpacker側では `rigor sig-gen` で生成されたRBSの品質指標として参考。

## Problem

rigorの自己精度カバレッジthresholdが43%だが、実測56.12%に対して13.12ポイントの余裕があり、gateとして機能していない。

**実測値:**
```
expressions typed: 121,249
precise:           68,051 (56.1%)
dynamic opaque:    53,198 (43.9%)
threshold:         43%
headroom:          +13.12pt
```

53,198個のdynamic式は改善余地が大きい。

## Worst-Performing Files

| File | Precision | Dynamic | cumulative % of all dynamic |
|------|-----------|---------|---------------------------|
| synthetic_method_scanner.rb | 37.9% | ~921 | 1.7% |
| sig_gen/writer.rb | 40.4% | ~756 | 3.1% |
| trace_renderer.rb | 44.6% | ~524 | 4.1% |
| incremental_session.rb | 30.5% | ~470 | 5.0% |
| conformance_checker.rb | 39.8% | ~397 | 5.7% |

これら5ファイルで全dynamicの5.7%を占める。

## Root Cause

- 32 gemsがRBSを持っていない (activesupport, concurrent-ruby, etc.)
- CLI renderer群は文字列処理中心でdynamicになりやすい
- incremental関連は複雑な状態遷移・JSON操作がdynamicの原因

## Proposed Solutions (rigor側)

1. **Threshold 43% → 50%** に段階的引き上げ (56%実績から6ptの余裕を残す)
2. **`rbs collection install`** でactivesupport, concurrent-ruby等のcommunity RBSを取得
3. **`dependencies.source_inference:`** を `.rigor.yml` に追加してRBS無しgemのフォールバック精度改善
4. **ワースト5ファイルの集中的なRBS / 型注釈追加**

## Acceptance Criteria (rigor側)

- Threshold 50%で一貫してpassすること
- Dynamic opaque率が40%未満になること
- `rbs.coverage.missing-gem` の件数が32→20以下に減少すること
