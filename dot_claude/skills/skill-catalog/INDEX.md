# Skill ルーティング表 (正本)

最終更新: 2026-07-02 / 使用実績データ: [USAGE.md](USAGE.md) (`scripts/generate.sh` で再生成)

**使い方**: タスクを始める前にこの表で入口 skill を 1 つ選ぶ。迷ったら「まず状況」→ 各セクションの
先頭にある太字の skill が入口。個別の下位 skill を直接呼ばない (入口が routing する)。

---

## 1. 実装タスクの入口 (どのパイプラインで作るか)

| 状況 | 使う skill | 補足 |
|---|---|---|
| 1〜2 ファイルの小修正 (30分以内) | **skill なしで直接** | パイプラインはオーバーヘッド |
| 仕様書・設計書が既にある実装 | `implement-from-spec` | Rust layered / TS onion + TDD |
| 調査が必要な中〜大機能 | `triple-research-dev` | 主力 (実績99回)。調査3並列→実装→レビュー |
| 配線保証・モック濫用防止が最重要 | `proven-done` | 重量級。境界変更 (DI/routing/auth/schema) で |
| レビュー往復付きの段階実装 | `codex-reviewed-impl` | ライブラリ的コード向け |
| TDD だけ強制したい | plugin `everything-claude-code:tdd` | 実績60回 (tdd-workflow) |

**選択基準**: 影響範囲が「境界」(DI/routing/auth/config/migration/schema/export) に触れるなら
proven-done、触れないなら triple-research-dev、仕様が固まっているなら implement-from-spec。

## 2. 設計・仕様の入口

| 状況 | 使う skill | 補足 |
|---|---|---|
| 設計・計画の反証と合意 | **`grill-me`** | 実績67回。実装前の standard |
| ADR を新規作成 | `adr-author` | 5-phase インタビュー |
| ADR の鮮度監査・改訂 | `adr-guard` | ADR↔コード乖離検出 + 改訂履歴 |
| 実装が仕様に即しているか | `spec-compliance-review` | 完了報告前の gate |
| ドメインモデリングのレビュー | `domain-modeling-review` | |
| アーキテクチャ規約の参照 | `onion-architecture` / `layered-architecture-dip` | |

## 3. 再開・状況把握の入口

| 状況 | 使う skill | 補足 |
|---|---|---|
| 「今日何する」「どこまでやったっけ」 | **`workspace-resume`** | dashboard / 再開ブリーフ / HANDOFF 保存 |
| どの skill を使うべきか迷った | `skill-catalog` | この表を読む |
| セッション終わり・区切り | `workspace-resume` save | HANDOFF.md 更新 |

## 4. 品質ゲート・改善ループの入口

| 状況 | 使う skill | 補足 |
|---|---|---|
| 完了報告の直前 | **`verify-before-completion`** | format/lint/test/spec-review 一括 |
| フェーズ分割作業の完了前 | `phase-handoff-check` | dangling handoff 検出 |
| 失敗・手戻りをルール化したい | `retrospective-codify` | ast-grep / skill / CLAUDE.md へ固定 |
| incident をガードへ昇格 | `self-improve` | 外側ループ (failure-miner→harness-maintainer) |
| skill/プロンプト自体の改善 | `empirical-prompt-tuning` | 実績18回。主力 skill の改良はこれ |
| 新規 repo にガード一式 | `agent-policy-kit` → `github-repo-rules` | scaffold → GitHub 設定 |

## 5. CI・ビルド修理の入口

| 状況 | 使う skill | 補足 |
|---|---|---|
| GitHub Actions が落ちた | **`ci-failure-fix`** | Rust / TS 検証込み |
| CI をローカルで再現 | `actrun` | 実績15回 |
| ビルドエラー | plugin `everything-claude-code:*-build-resolver` agent | 言語別 |

## 6. アイデア・発信の入口

| 状況 | 使う skill | 補足 |
|---|---|---|
| アイデア出し全般 | **`idea-orchestrator`** | 唯一の入口。idea-* 9 種は直接呼ばない |
| ブログ執筆 | `mizchi-blog-style` (文体参考) / `insights-ja` | |
| 技術記事の再現性チェック | `tech-article-reproducibility` | |

## 7. アセット生成の入口

| 状況 | 使う skill | 補足 |
|---|---|---|
| Another Me 素材全般 | **`another-me-generate-sprite-assets`** | 唯一の入口。character/object/scene へ routing |
| その他ゲーム素材 | `spritecook-generate-sprites` + `spritecook-workflow-essentials` | |

## 8. 特定技術リファレンス (必要時に参照)

`cloudflare` / `wrangler` / `workers-best-practices` / `durable-objects` / `sandbox-sdk` /
`agents-sdk` / `devbox` / `nix-setup` / `moonbit-js-binding` / `next-best-practices` /
`vercel-react-best-practices` (実績44回) / `web-perf` / `playwright-cli` / `playwright-test` /
`justfile` / `dotenvx` / `drawio` / `library-docs` / `context7-mcp`

---

## 運用ルール

1. **新 skill を作る前に**この表と USAGE.md を確認し、既存 skill の改良 (`empirical-prompt-tuning`)
   で済まないか判断する。済むなら新設しない。
2. **月1回** `scripts/generate.sh` を実行し、未使用 skill の増減を確認する。
   3ヶ月連続未使用の skill はアーカイブ候補 (`~/.claude/skills/_archive/` へ移動) として提案する。
3. この INDEX.md の分類・推奨は手動管理。USAGE.md の実績と乖離したら更新する。
4. 正本は dotfiles repo (`dot_claude/skills/skill-catalog/INDEX.md`)。編集したら dotfiles にも反映する。
