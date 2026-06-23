# 01 — binpacker LPT scheduling balance improvement

Status: needs-triage

## Problem

binpackerのLPTスケジューリングが4ワーカー間で6.4%の偏在 (max deviation 21.3s) を生んでいる。タイミングデータがキャッシュから正常に復元されていても、最速Worker(5m19.3s)と最遅Worker(5m54.5s)の間に35.2sの開きがある。

**実測データ** (PR #29 CI run 28034424567):

| Worker | Files | Examples | Time | s/file | s/example |
|--------|-------|----------|------|--------|-----------|
| W0 | 70 | 1703 | 5m54.5s | 5.06 | 0.208 |
| W1 | 72 | 1890 | 5m29.4s | 4.58 | 0.174 |
| W2 | 74 | 1565 | 5m19.3s | 4.31 | 0.204 |
| W3 | 74 | 1861 | 5m29.8s | 4.46 | 0.177 |

Total: 290 files, 22m13.1s (1333s)
Perfect 4-way split: 333s/worker
Current slowest: 354.5s → **21.5s waste (6.4%)**

## Root Cause

- ファイル数ベースでは70-74で均衡しているが、per-file runtimeに17.4%のばらつき
- Example数も1565-1890で20.5%の幅
- LPTはファイル粒度でのスケジューリングであり、1ファイル内の重いexampleを分割できない
- タイミングデータは前回runから復元されているが、コード変更によりファイルごとの実行時間が変化している可能性

## Proposed Solutions

1. **Multifit algorithm** (binpacker roadmap 記載済み): LPT初期分割にbinary-search最適化パスを追加
2. **Per-file timing decay weighting**: タイミングデータが古いファイルほど重みを増す
3. **Outlier detection**: 極端に重いspecファイルを自動検出し、ファイル内でexample分割 or 専用workerアサイン
4. **Work-stealing enhancement**: 現状のsteal有効時の挙動を検証、アイドルworkerが他workerから動的取得する閾値調整

## Acceptance Criteria

- 4 worker環境でmax deviation 3%未満 (< 10s)
- タイミングデータがない初回runでもfilesize weightingで同等のバランスを達成
- 回帰テスト: 既存のバランステストがパスすること
