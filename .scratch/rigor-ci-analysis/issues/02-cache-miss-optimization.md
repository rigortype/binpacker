# 02 — Warm job cache miss optimization (CI)

Status: needs-triage

**Note:** このIssueは主に rigortype/rigor リポジトリのCIワークフローに関するもの。binpacker側では `.github/workflows/ci.yml` に該当テンプレがある場合の参考値として記録。

## Problem

Self-check (warm) job が依存関係bump PRで常にcache missする。キャッシュキーに `hashFiles('Gemfile.lock')` が含まれているため、Gemfile.lock変更時は確実に既存キャッシュが使えず、warm jobは実質coldと同一の分析（16.41s）を実行する。

**実測データ:**
```
Cache not found for input keys: rigor-cache-Linux-<lockfile hash>-<source hash>
```

warm jobは29s消費し (setup 含む)、coldと同一のdiagnosticsを出力 → diff gateは自明pass。リソースの無駄。

## Impact

依存bump PR（Dependabot / Renovate経由を含む）で毎回:
- 29sのwarm job実行時間 (setup + 16.41s分析)
- Runner resourceの無駄
- 本来はwarmを待つ必要があるfan-in gateの待ち時間増加

## Proposed Solutions

1. **Cache key existence check**: warm jobの最初のstepで `actions/cache@v5` の `lookup-only: true` でキー存在確認 → miss時はskipし、diff gateもpass扱い
2. **Path filter**: Gemfile.lock変更時のみwarm matrixから除外 (ただし `.github/workflows/ci.yml` の変更も考慮)
3. **restore-keys fallback改善**: 現状のrestore-keysはlockfile hash prefixで一致を試みるが、lockfile hashが異なるとprefixも異なる。代わりにOS情報のみでfallbackできる別のrestore-keyを追加

## Acceptance Criteria

- Gemfile.lock変更PRでwarm jobがskipまたは即時passされる
- コード変更PR (lockfile不変) では従来通りwarm == cold diffを実行
- Skip時も後続のdiff gateやfan-in CI requiredがblockされない
