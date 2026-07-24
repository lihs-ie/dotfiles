# Spec: idchain

<!-- /grill-me 合意 (2026-07-24) から正規化。出典: 発表資料「『動くだけ』のその先へ — AI駆動開発で品質と速度を両取りする温故知新な新手法」(AI Dev EX Conference 2026-07-23) の ID トレーサビリティ連鎖 (p.36-43, 64-74) を逆転拡張したもの。 -->

## Goal

- 仕様・テスト設計・検証を双方向に追跡できる「ID の鎖」で、ディスカバリーから学び台帳までの
  **フルライフサイクルを一気通貫で開発する汎用ポータブルハーネス「idchain」** を dotfiles に完全新規構築する。
- 発表資料の構造を 1 点逆転する: **正本 = Lean 4 形式仕様** (機械が数学的に証明する対象) とし、
  人間が読む文書 (仕様書・テスト設計書・Why/What・学び台帳の各ビュー) は**形式仕様からの生成物**とする。
- 「やったか」は決定論的に常時・全件チェック (ID の鎖・テスト実行・ビルド)、
  「正しいか」はモデル証明 + 独立 AI レビューで担保する (発表 p.41 の二層構造)。
- 旧 agent-policy kit とその開発フローは**廃止予定のため一切依存しない** (完全新規)。
  chezmoi の配布経路 (dot_claude → ~/.claude) のみ再利用する。

## 全体アーキテクチャ (合意済み設計)

### ID 体系

| Prefix | 意味 | 例 |
|---|---|---|
| PB | 顧客課題 (Problem) | PB-001 |
| VL | 提供価値 (Value、PB とペア必須) | VL-001 |
| FA | 機能領域 (Feature Area、How へ 1:N) | FA-001 |
| HY | 仮説 (反証可能形式: 観測可能指標 + 閾値) | HY-001 |
| SP | 仕様文 (発表の `#047` に相当) | SP-047 |
| TC | テストケース (`TC-<SP番号>-<枝番>` で導出元を埋め込む) | TC-047-1 |
| LL | 学び台帳エントリ (append-only) | LL-001 |

- ゼロ埋め 3 桁・プロジェクト内で単調増加・欠番許容・**再利用禁止**。
- 検証レポートは ID を持たない日付きスナップショット。

### 正本と生成物

- 正本: 対象 repo の `idchain/Canon/*.lean` (全 7 種アーティファクトを Lean の型のインスタンスとして定義)。
- 生成物: `idchain/views/*.md` (DO NOT EDIT ヘッダ付き)。鮮度は再生成 diff で機械検査。
- 検証レポート: `idchain/reports/<日付>/` に MD + JSON。
- engine (型定義 + 全 lake exe) の正本は `dot_claude/idchain/engine/` (→ `~/.claude/idchain/engine/` に配布)。
  対象 repo へは **init 時に vendoring** (hermetic CI のため。更新は `idchain init --update`)。

### 証明境界 (モデル証明 + テスト検証)

- Lean 内で証明するもの: トレーサビリティ制約 (decidable 検査 = 計算による証明)、
  仕様同士の**無矛盾性** (全 SP の invariant を満たす witness モデルの構成。
  witness と証明が閉じない限り check exe 自体がコンパイルできない構造にする)。
- 実装コード (対象 repo の Swift/TS/Rust 等) は鎖の外 (発表 p.36「実装は連鎖には入らない」)。
  正しさは TC 由来テストの実行結果で検証する。

### 人間ゲート (3 点のみ、他は AI 自走)

| ゲート | 位置 | 承認内容 |
|---|---|---|
| G1 | Why/What 確定 | 課題・価値・合格ライン (PB/VL/FA/HY) |
| G2 | 仕様承認 | 形式検査パス後・実装着手前 (SP) |
| G3 | 成果レビュー | 合格ライン vs 計測値の判定 (retro) |

- 承認は Lean 正本に埋込み、**内容の正準直列化 + FNV-1a 64bit ハッシュに束縛**
  (承認後の改変 = ハッシュ不一致で自動失効)。書込は approve コマンド経由のみ、真正性は git 履歴で担保。
- 「意思の痕跡」(何を棄てたか・なぜ選んだか) も正本のフィールド。「要証拠」空欄は型付き未充足フィールドでゲート遮断。

### 操作体系 (少数フェーズ型) と四層強制

- skills: `idchain-discovery` / `idchain-spec` / `idchain-build` / `idchain-retro` + 補助 `idchain-init` / `idchain-approve`。
- 強制点: ① skill 内ゲート ② pre-commit (init が導入) ③ CI テンプレート (全件: 証明ビルド + 突合 + 鮮度)
  ④ Claude Code PreToolUse 編集ブロック hook (`idchain/` 保有 repo でのみ発火)。
- 周辺ツール (exporter・突合・ビュー生成・レポート生成) も **lake exe で Lean に統一** (二重定義ゼロ)。

## Must — M1: コア鎖

- [ ] **Must-1 (engine package)**: `dot_claude/idchain/engine/` に lake package が存在し、
      `lean-toolchain` が `leanprover/lean4:v4.32.1` にピン留めされ、依存ゼロまたは Batteries のみで
      `lake build` が exit 0。
- [ ] **Must-2 (ID 型)**: 7 prefix の ID 型が parse/render 往復同一性を持ち (`#guard` 等で機械検証)、
      TC は `TC-<SP番号>-<枝番>` の複合構造で親 SP 番号を型として保持する。
- [ ] **Must-3 (Registry)**: 7 種アーティファクトの構造体と Registry 集約が存在し、
      ID 一意性・単調増加・欠番許容・再利用禁止 (retired ID 台帳との衝突検査) が decidable 検査で判定される。
- [ ] **Must-4 (トレーサビリティ検査)**: 以下が全て decidable 検査として実装され、違反が ID 付きで報告される:
      (a) 承認済 SP に TC が 0 件 (orphan spec)、(b) TC の親 SP が不在または未承認、
      (c) VL に対応 PB が不在 (ペア必須)、(d) SP の FA 帰属が不在、(e) HY の PB/VL 参照が不在、
      (f) LL の削除 (append-only 違反)。
- [ ] **Must-5 (承認ハッシュ)**: 承認対象アーティファクトの正準直列化 + FNV-1a 64bit ハッシュを
      approval が保持し、現内容とのハッシュ不一致 = 承認失効として検査が失敗する。
- [ ] **Must-6 (無矛盾性証明)**: プロジェクト状態型 σ 上で各 SP が `invariant : σ → Prop` を持ち、
      witness モデル + 全 invariant 成立の証明を `Canon/Gate.lean` が提供しない限り
      check exe がコンパイルできない構造になっている。
- [ ] **Must-7 (check exe)**: `lake exe idchain check` が Must-3〜5 の全検査を実行し、
      違反 0 なら exit 0、違反ありなら exit 1 + 違反一覧 (ID + 種別 + 修正指針) を出力する。
- [ ] **Must-8 (export exe)**: `lake exe idchain export` が TC 一覧・ID inventory を JSON で出力する。
- [ ] **Must-9 (crosscheck exe)**: `lake exe idchain crosscheck` が `idchain.json`
      (テストファイル glob・xunit XML パス・テストコマンド) を読み、テストコード内の TC ID 走査と
      xunit 実行結果を**双方向突合**し、(a) TC ID を持たないテスト、(b) 未知の TC ID を名乗るテスト、
      (c) テストコードに存在しない TC、(d) 実行されなかった TC、を全件報告する。
- [ ] **Must-10 (views exe)**: `lake exe idchain views` が仕様書・テスト設計書・Why/What・学び台帳の
      人間向け MD (DO NOT EDIT ヘッダ付き) を `views/` に生成し、`--check` で再生成 diff による鮮度検査ができる。
- [ ] **Must-11 (report exe)**: `lake exe idchain report` が check + crosscheck + テスト結果から
      SP 毎 PASS/FAIL の検証レポート (MD + JSON) を `reports/<日付>/` に生成し、
      「検証に紐づいていない仕様: N 件 / 仕様に紐づいていないテスト: N 件」(発表 p.37) を必ず含む。
- [ ] **Must-12 (approve exe)**: `lake exe idchain approve <ID> --by <承認者> --note <判断根拠>` が
      現内容ハッシュを計算して承認を `Canon/Approvals.lean` に書き込む。approve 経由以外の
      Approvals.lean 変更は CI が警告する。
- [ ] **Must-13 (init exe)**: `lake exe idchain init <target>` が対象 repo に
      engine vendoring・`lean-toolchain`・`idchain.json`・Canon スケルトン・pre-commit hook・
      CI workflow テンプレートを導入し、`--update` で engine のみ再同期できる。
- [ ] **Must-14 (M1 skills)**: `dot_claude/skills/` に `idchain-init` / `idchain-spec` / `idchain-build` /
      `idchain-approve` が存在し、G2 ゲートと決定論的ゲート (check→views→crosscheck→report) の
      実行順序が手順として明文化されている。
- [ ] **Must-15 (fixture 実証)**: `tests/fixtures/idchain-sample/` に正例 (全 7 種アーティファクト +
      無矛盾性証明 + TC 突合パス + report green) が存在し、負例 5 種以上
      (orphan SP / 未承認 SP の TC / ハッシュ失効 / 孤児テスト / ID 再利用) が check または crosscheck の
      exit 1 で検出されることを dotfiles の tests が実行検証する。

## Must — M2: 上流 + retro

- [ ] **Must-16 (discovery)**: `idchain-discovery` skill がダブルダイヤモンド手順 (広げてから絞る×2)・
      棄却案の記録 (意思の痕跡)・HY の反証可能形式 (観測可能指標 + 閾値) 起票・「要証拠」空欄の
      型フィールド化・G1 承認を含む。
- [ ] **Must-17 (retro)**: `idchain-retro` skill が成果レビュー (先に固定した合格ライン vs 計測値入力)・
      LL 追記 (外れた仮説も削除禁止)・G3 承認・ロードマップ書き換えを含み、
      LL の append-only 性が decidable 検査される。

## Must — M3: 付帯機構

- [ ] **Must-18 (独立レビュー)**: `idchain-build` が実装コンテキストを共有しない reviewer subagent の
      起動を必須手順とし、レビュー結果が検証レポートに記録される。
- [ ] **Must-19 (オラクル TC)**: TC の variant として oracle 型 (複数エンジンへの同一クエリ + 一致判定) を
      型定義し、crosscheck/report が一致・不一致を判定する。
- [ ] **Must-20 (ペアワイズ)**: 因子・水準を Canon に定義し `lake exe idchain pairwise` が
      全 2 因子ペア網羅の構成一覧を生成、網羅率 100% を自己検証して出力する。
- [ ] **Must-21 (ベンチ)**: `idchain.json` のベンチコマンド + 閾値定義を読み `lake exe idchain bench` が
      実行・収集・赤黄緑判定し、結果が検証レポートに記録される。

## Must — M4: 編集ブロック hook + 実適用

- [ ] **Must-22 (編集ブロック hook)**: PreToolUse hook が `idchain/` 保有 repo でのみ発火し、
      未承認 SP しか存在しない状態での実装ファイル編集 (idchain/・テストパス以外への Edit/Write) を
      deny する。例外は `idchain.json` の allowlist で管理する。
- [ ] **Must-23 (recall-paper 実適用)**: recall-paper (Swift) に init 済みで、実サイクル 1 周
      (PB→VL→FA→HY→SP 承認→TC→実装→検証レポート green→retro) の成果物が recall-paper repo に存在する。

## Should

- [ ] Should-1: views の出力は日本語 (発表資料の語彙: 仕様書・テスト設計書・検証レポート に揃える)。
- [ ] Should-2: oracle / bench 未設定プロジェクトでは該当検査を「未設定」として graceful skip
      (エラーにしない。ただし report に未設定である旨を明記)。
- [ ] Should-3: mathlib 非依存を維持する (証明が要求した時点でユーザーへエスカレーション)。
- [ ] Should-4: crosscheck の xunit アダプタは swift test (xunit XML) を初期対応とし、
      形式追加が adapter 設定で拡張可能な構造にする。

## Non-goals

- 旧 agent-policy kit の撤去・修正 (別タスク。本タスクでは一切触れない)。
- 実装コードの証明 (Lean 実装抽出・Dafny 等)。実装は鎖の外。
- BizDev プロトタイピング支援層 (発表 p.71)。
- GitHub PR 承認駆動の承認管理 (承認は Lean 正本埋込 + git 履歴で足りる)。
- 発表 p.45 のディープリサーチ自動注入 (ベンチ赤黄緑判定までが M3 スコープ)。

## 受入条件 (全体 done の定義)

1. dotfiles の fixture テストが green (`tests/` から実行、正例 + 負例全件)。
2. 各 lake exe の exit code / 出力を実行 assert したコマンドログが存在する。
3. recall-paper で実サイクル 1 周が完了し、検証レポートに孤児 0 件の数値が刻まれている。
4. chezmoi apply 後に `~/.claude/idchain/` と skills が配布されている。

## マイルストーン

| Milestone | 範囲 | 対応 Must |
|---|---|---|
| M1 | コア鎖 (engine・全 lake exe・M1 skills・fixture) | Must-1〜15 |
| M2 | 上流 + retro (discovery/retro skills・G1/G3) | Must-16〜17 |
| M3 | 付帯機構 (独立レビュー・オラクル・ペアワイズ・ベンチ) | Must-18〜21 |
| M4 | 編集ブロック hook + recall-paper 実適用 | Must-22〜23 |

## リスク (合意済み受容)

- 四層強制 (編集ブロック hook) の運用負荷 → ユーザー裁定で採用。誤爆防止は `idchain/` 保有判定 + allowlist。
- 付帯機構 4 種全部入り + Lean exe 統一は初回構築として最大級 → M1-M4 段階分割で吸収。
- Lean での XML parse / glob / hash は自前実装 (Batteries 圏内)。対象は限定的で一度書けば安定。
- idchain 自身の開発は既存グローバル規約 (plan → TDD → review) で行い、完成後に idchain 自身を dogfood する。
