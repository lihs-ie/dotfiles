---
name: adr-guard
description: ADR (Architecture Decision Record) と実コードの乖離を検出し、改訂履歴を規約化して整合性を維持する。Use when (1) ユーザーが「ADR 監査して」「ADR が古くなってないか」「ADR とコードの整合性チェック」「ADR の改訂管理」と言ったとき、(2) /adr-guard [repository] を実行したとき、(3) 大きめのリファクタリング・境界変更 (schema/routing/DI) の後に ADR 更新の要否を確認したいとき。scripts/adr-drift-scan.sh が ADR の最終更新と scope 対象コードのコミット履歴を比較して DRIFT/FRESH/NO-SCOPE に分類し、DRIFT は「確認・改訂・廃止」のいずれかに落とす。ADR の新規作成は adr-author を使う (このskill は既存 ADR の維持管理専用)。
---

# ADR Guard

ADR は「書いた時点」では正しいが、コードが進むと黙って嘘になる。この skill は
**ADR より後に対象コードが変わったものを機械検出**し、改訂履歴として記録することで
「ADR の執筆・整合性・修正履歴管理」のコストを下げる。

役割分担: 新規作成 = `adr-author` / 実装が仕様に従っているかのレビュー = `spec-compliance-review` /
**既存 ADR の鮮度維持 = この skill**。

## 手順

### 1. スキャン

```bash
bash ~/.claude/skills/adr-guard/scripts/adr-drift-scan.sh [repository_root]
```

- 読み取り専用。ADR ディレクトリ (docs/adr, adr 等) を自動検出する
- 各 ADR を `[DRIFT]` / `[FRESH]` / `[NO-SCOPE]` に分類して出力する
- ADR 保有リポジトリ (2026-07 時点): pschool, recall-paper, native-trace, cloudflare-workers-hs。
  「全部監査して」と言われたらこの 4 つを順に回す

### 2. DRIFT の裁定

各 `[DRIFT]` ADR について、ADR 本文と scope パスの `git log` / 必要なら diff を読み、
以下の 3 択に裁定する。**裁定案を表で提示し、ユーザー承認を得てから書き込む**こと。

| 裁定 | 条件 | アクション |
|---|---|---|
| 確認 (still valid) | コードは変わったが決定内容はまだ正しい | 改訂履歴に「確認」行を 1 行追記 |
| 改訂 (revise) | 決定の一部が現実と食い違う | 本文修正 + 改訂履歴に「改訂」行を追記 |
| 廃止 (supersede) | 決定自体が置き換わった | Status を Superseded に変更 + 後継 ADR を `adr-author` で起案 |

### 3. NO-SCOPE の解消

`[NO-SCOPE]` の ADR には本文に `Scope:` 行を追加する (これも承認後に書き込み):

```markdown
Scope: pschool/schema/, pschool/course_builder/models.py
```

- repo 相対パス、カンマ区切り。ディレクトリ可
- 以後のスキャンはこの行を機械的に読む (backtick 推測より確実)

## 改訂履歴の規約

すべての ADR の末尾に以下のセクションを持たせる。scan が「改訂履歴: なし」と報告した
ADR に対しては、次に触るタイミングで追加する。

```markdown
## 改訂履歴

| 日付 | 種別 | 内容 | 契機 |
|---|---|---|---|
| 2026-07-02 | 確認 | schema/ の変更 12 commits を確認、決定は有効 | abc1234 |
| 2026-05-20 | 制定 | 初版 | - |
```

- 種別: 制定 / 確認 / 改訂 / 廃止
- 契機: コミットハッシュ、PR 番号、または「定期監査」

## 運用

- **タイミング**: 境界変更 (schema / routing / DI / auth / export) を含む PR のマージ後、
  および月 1 回の定期監査 (workspace-resume の dashboard と同時が楽)
- **adr-author との連携**: 新規 ADR には作成時点で `Scope:` 行と `## 改訂履歴` (制定行のみ) を
  含めるよう adr-author に依頼する
- **禁止**: 承認なしの ADR 本文書き換え / DRIFT の一括自動「確認」処理 (1 件ずつ裁定する)
