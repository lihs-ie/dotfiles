# idchain 用語集

調査基準: `lihs-ie/dotfiles` commit `ae5d75bc3b63b96f563f497bff09f16fad01b182`。
用語の意味は現時点の正本・Skill・engine実装に限定する。

## ドメイン用語

| 用語 | 意味 | 分類 | 主な実装・参照 | 注意点 | 確度 |
|---|---|---|---|---|---|
| idchain | ディスカバリーから学びまでを識別子で接続し、Leanと決定論的検査で工程ゲートを強制する開発ハーネス | 組織内用語 | [idchain仕様](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/docs/specs/idchain.md) | 単なる採番規約ではなく、承認・検証・学びを含む | confirmed |
| Canon | 対象repoの `idchain/Canon/*.lean` に置く唯一の正本 | 実装固有名 | [engine registry](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/idchain/engine/Idchain/Registry.lean) | `views/*.md` はCanonから生成されるため正本ではない | confirmed |
| IDの鎖 | PB→VL→FA→SP→TCと、HY・LL・RMを参照関係で追跡できる状態 | ドメイン用語 | [決定論的検査](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/idchain/engine/Idchain/Checks.lean) | 実装コード自体は鎖の外に置き、TC由来テストで接続する | confirmed |
| 決定論的ゲート | `lake build`、`check`、`crosscheck`、`views --check`、`report` など、同一入力から同一判定を返す検査 | ドメイン用語 | [CLI](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/idchain/engine/Idchain/Cli.lean) | AIレビューによる意味検査とは役割が異なる | confirmed |
| 意味一致レビュー | SP本文・invariant・境界値の意味が一致するかを、実装コンテキストを持たない別エージェントが判定する検査 | ドメイン用語 | [idchain-spec Skill](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/skills/idchain-spec/SKILL.md) | G2の承認操作ではなく、その前提となる独立検査 | confirmed |
| fresh approval | 現在の正準直列化ハッシュと承認時ハッシュが一致している承認 | 実装固有名 | [Approval](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/dot_claude/idchain/engine/Idchain/Approval.lean) | 承認後に内容を変えると自動失効する | confirmed |
| 四層強制 | Skill内ゲート、pre-commit、CI、エージェントの編集直前hookを重ねる方式 | 組織内用語 | [idchain仕様 Must-22](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/docs/specs/idchain.md) | Codexでは標準編集経路 `apply_patch` をhookが担当し、shell変更はpre-commit/CIが補完する | confirmed |

## 識別子

| Prefix | 概念 | 意味 | 混同しやすい点 | 確度 |
|---|---|---|---|---|
| PB | Problem | 顧客課題 | 解決策ではなく、解くべき問題を表す | confirmed |
| VL | Value | 提供価値と合格ライン | PBとの対応が必須 | confirmed |
| FA | Feature Area | 価値と仕様を接続する機能領域 | 個別仕様SPより上位 | confirmed |
| HY | Hypothesis | 観測可能な指標と閾値を持つ反証可能な仮説 | 願望や気持ちだけでは成立しない | confirmed |
| SP | Specification | 形式検査・意味一致レビュー・G2承認の対象となる仕様 | 発表資料の `#047` に相当 | confirmed |
| TC | Test Case | SPから導出されるテスト設計 | `TC-<SP番号>-<枝番>` で親SPを埋め込む | confirmed |
| LL | Learning | 成果判定から得たappend-onlyの学び | 外れた仮説も削除しない | confirmed |
| RM | Roadmap Item | 仮説・学び・ベンチ結果を次の開発周期へ反映する項目 | `dropped` でも削除しない | confirmed |

## ゲート

| 用語 | 承認対象 | 位置 | 確度 |
|---|---|---|---|
| G1 | PB/VL/FA/HYのWhy/Whatと合格ライン | discovery完了時 | confirmed |
| G2 | 形式検査と意味一致レビューを通過したSP | TC導出・実装着手前 | confirmed |
| G3 | 合格ラインと実測値の比較、HY判定、LL | release後のretro | confirmed |

## Codexホスト用語

| 用語 | 意味 | 根拠 | 注意点 | 確度 |
|---|---|---|---|---|
| 論理正本 | `dot_claude/` に保持する共通engineとSkill手順 | [idchain仕様](https://github.com/lihs-ie/dotfiles/blob/ae5d75bc3b63b96f563f497bff09f16fad01b182/docs/specs/idchain.md) | Claude専用という意味ではなく、重複を避けるauthoring location | confirmed |
| Codex配布実体 | chezmoiが `dot_codex/` と同期scriptから `~/.codex/` に構成するSkill・hook・engine | [Codex Hooks公式仕様](https://learn.chatgpt.com/docs/hooks) | hook定義を変更するとCodexで再信頼が必要 | confirmed |
| engine digest | `.lake` 等を除くengine正本全ファイルから決定論的に算出するSHA-256 | repository sync scripts | 正本更新後にdigest未更新なら同期検査が失敗する | confirmed |
| fail-open | tool入力から対象パスを抽出できない場合、hook単体では止めず後段ゲートへ委ねる挙動 | Codex hook adapter | idchain対象パスと判明した後のgate-status欠落はfail-closed | confirmed |
