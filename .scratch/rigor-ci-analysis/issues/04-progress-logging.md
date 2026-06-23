# 04 — binpacker progress logging anomaly

Status: needs-triage

## Problem

CI実行中の進捗ログで不整合な表示が確認された。総実行時間358s時点でWorker 0が完了表示されている一方、他の3ワーカーが0/N表示となっている。

**実測ログ:**
```
[binpacker 358.0s] W0: done | W1: 0/72 | W2: 0/74 | W3: 0/74
```

しかし最終結果では全ワーカー正常完了:
```
Worker 0: 70 files, 5m54.5s | 1703 examples
Worker 1: 72 files, 5m29.4s | 1890 examples
Worker 2: 74 files, 5m19.3s | 1565 examples
Worker 3: 74 files, 5m29.8s | 1861 examples
```

W0完了時(354.5s)にW1-3のカウントが0で表示されるのは、W0が最後に進捗報告したタイミングで他ワーカーが最初のバッチ完了報告をまだ行っていなかったためと推測される。

## Impact

- **Low** — パフォーマンスや正確性に影響なし
- CIログを読む開発者にとって「本当に動いているのか」と不安になる
- 長時間実行 (~6分) の進捗可視性が低下する

## Proposed Solutions

1. **進捗表示の初期化**: Worker起動時に "0/N" を表示してから最初のバッチを開始する
2. **最後の進捗報告からの経過時間表示**: "W1: 0/72 (last report 45s ago)" など
3. **定期的なheartbeat**: 進捗がないWorkerも定間隔でalive signalを送信
4. **完了Workerの経過時間を他の行と揃える**: "done" ではなく "W0: 70/70 (5m54s)" のような形式に統一

## Acceptance Criteria

- 全Workerの進捗が常に0/N以上で表示される (未完了Workerが0/Nと表示されない)
- Worker完了時の表記が他の行と形式が揃っている
- CIログで各Workerの生存が確認可能
