---
name: z3-tla-playbook
description: 仕様書が無い / あてにならない / 実装とずれている既存システムに対し、実装を「事実上の仕様」とみなして吸い出し、Z3 (SMT) と TLA+ (モデル検査) で反例を払い出す。テストでは踏めないバグ (設定の矛盾・被覆の穴・read-modify-write レース・結果整合による上限超過・エラーを boolean に畳んだ否定の化け・信頼境界の詐称・クロス境界の表現契約ずれ) を機械に探させ、出た反例を「これは意図か?」とドメインにぶつけて仕様として明文化するかバグとして直すかを決める。Use when (1) ユーザーが「形式手法で検証」「Z3 で検査」「TLA+ でモデル検査」「反例を出して」「実装から仕様を吸い出して」「並行バグを洗い出して」「この設定は矛盾していないか」「不変条件を証明して」と言ったとき、(2) /z3-tla-playbook を実行したとき、(3) 仕様書が存在しない legacy 実装のバグ探索・リファクタ前後の等価性確認・設定ルールの整合性検査に着手するとき、(4) 並行 / リトライ / 上限 / キャッシュ / 権限判定 のように「全順序で成り立つべき」性質を扱うとき。仕様書が既にある実装の照合は spec-compliance-review、プロダクト↔ドメイン理論の整合性は domain-integrity-audit を使う (この skill は仕様が無い前提の吸い出し専用)。scripts/setup-env.sh が z3-solver + tla2tools.jar を lockfile 化し、scripts/run-checks.sh が self-check と broken-variant で「検査が実際に効いている」ことまで強制する。
---

# z3-tla-playbook

**コードが de-facto 仕様である**という立場を取る。仕様書ではなく実装が現に何をしているかを
仕様の源にして、3 段で回す:

1. **吸い出し (extract)** — 実装から「主張している仕様」と「暗黙に決めている挙動」を**分けて**抜く
2. **反例探索 (refute)** — 主張をモデル化し、全入力 / 全順序で本当に成り立つかを機械に攻撃させる
3. **突き合わせ (reconcile)** — 出た反例を「これは意図か?」とドメイン知識のある人にぶつける
   → 意図なら**仕様として明文化**、意図でないなら**バグ**

反例はバグ報告であると同時に **認識合わせの会話の起点**。ここが一番効く。

> 方法論の出典: mizchi「実装コードから仕様を吸い出して Z3 / TLA+ でバグを払い出す — 実践プレイブック」
> <https://gist.github.com/mizchi/db7817e6fc077d567c41cd9d41bb1c53> (2026-07-25 参照)。
> 本 skill は上記を、この環境の実行ハーネスと台帳運用に落とし込んだ派生物。

## 他 skill との役割分担

| 状況 | 使うもの |
|---|---|
| **仕様書が無い / あてにならない** 実装のバグ払い出し | **この skill** |
| 仕様書が既にある実装との照合 | `spec-compliance-review` |
| プロダクト↔ドメイン理論の整合性 | `domain-integrity-audit` |
| ADR とコードの乖離検出 | `adr-guard` |
| 計画・設計の反証 (人間相手) | `grill-me` |
| 配線保証つきの実装パイプライン | `proven-done` (この skill は**その前段**。spec が無い legacy に入口を作る) |
| 反例を仕様 (SP) とテストケース (TC) に固定する | `idchain-spec` (この skill の出口。HOLDS を契約に、REFUTED を TC 候補にする) |

## 0. 環境

```bash
SKILL=~/.claude/skills/z3-tla-playbook
bash $SKILL/scripts/setup-env.sh --dir .formal --init       # 検証ディレクトリと雛形
bash $SKILL/scripts/setup-env.sh --dir .formal --install    # z3-solver + tla2tools.jar
bash $SKILL/scripts/setup-env.sh --dir .formal --check      # lock と実環境の照合
```

`.formal/formal-lock.json` に**実際に入った版**を記録する (推測値を書かない)。
`.venv/` と `tools/` は commit しない — lock だけが版の正本。

## 1. ツールの使い分け

| | Z3 (SMT) | TLA+ (TLC) |
|---|---|---|
| 問い | **全入力に対して、ある一瞬** | **時間を通じて、全順序・全 interleaving** |
| 得意 | 純粋述語 / 設定・ルールの整合性 | ステートフルなプロトコル / 並行 / 状態遷移 |
| model↔code gap | 狭い (対象がデータなら実データを直接食える) | 広い (命令型を手で抽象する) |
| 置き場所 | 保存時 validator / CI の静的検査 | 設計レビューの成果物・回帰ガード |

**判定フロー:**

- 「この条件、**どんな入力でも**成り立つ?」「この設定、**配信され得る**?」
  → 述語が区間 + 集合 + 等式の decidable fragment なら **Z3**
- 「**どの順番で起きても**大丈夫?」「同時に来たら?」「クラッシュ後は?」「いつか必ず〜する?」
  → 状態遷移 + 非決定性 → **TLA+**
- **状態空間が有限で決定的なら、素の全列挙 (プログラムで直積を回す) が一番安い。**
  ツールを持ち出す前に「有限か? 決定的か?」を必ず問う

## 2. 1 周のワークフロー

### Step 1 — 対象領域を選ぶ
`reference/bug-catalog.md` で「ありそうな型」を 2〜3 個当てる。当てずに全部を形式化しない。

### Step 2 — 実装を読んで吸い出す
`reference/extraction-questions.md` の 8 つの問いを**機械的に**投げる。
「宣言された仕様」と「暗黙の挙動」を分けて `.formal/ledger.md` の A 欄に **file:line 付き**で記録する。

**実装を読まずに要約・記憶からモデルを組まない。** 変換テーブルを 1 つ取り違えると偽の証明になる。

### Step 3 — 決定関数と invariant を書く
- 配管 (I/O・フレームワーク・DB) を剥がした純粋関数 `predict(state)` として書く
- 証明したい性質に**名前を付ける** (`NeverOverCap == served <= cap`)
- **成立を証明したいのか、反例が欲しいのか**を決めてから invariant を立てる
- 境界 (`cap-1`, `cap`, `cap+1`) と空集合を定義域に必ず入れる

雛形: `.formal/models/example_cap.py` (Z3) / `.formal/specs/Example.tla` (TLA+)。

### Step 4 — 回す
```bash
bash $SKILL/scripts/run-checks.sh --dir .formal
```
このハーネスは 3 つを同時に強制する:
1. **self-check** — 各モデルが期待判定 (HOLDS/REFUTED, OK/VIOLATE) と一致するか
2. **broken-variant** — わざと壊した変種が**赤で捕まる**か。捕まらなければその検査は何も守っていない
3. **空でないこと** — モデル 0 件の「空っぽの緑」を失格にする

`.formal/models/broken/<stem>__<label>.py` と `.formal/specs/broken/<Stem>__<Label>.tla`
に対照を置く。**対照が無いモデルは失格になる** (`--allow-missing-broken` で一時回避可)。

### Step 5 — 結果を台帳に落とす
- **反例が出た** → witness 付きで「これは意図か?」をドメインに問う (`ledger.md` C 欄)
- **成立を証明できた** → **契約 (regression guard) としてロック** (`ledger.md` B 欄)

両方揃うと「何が保証され / 何が穴か」の台帳になる。

### Step 6 — CI に載せる
`run-checks.sh` は人間可読な出力と機械可読な exit code を両方出す。
ローカルと CI が**同一のハーネスを叩く** (実行経路を 1 つにする)。

### Step 7 — model ↔ code のギャップを詰める
形式手法は「書いたモデル」を検証するのであってコードそのものではない。

- **対象がデータ (設定・ルール) なら gap は狭い** — 実データを validator に流す変換層を書けば、
  証明対象と本番がほぼ一致する
- **対象が命令型・並行コードなら gap は広い** — 価値は「設計の妥当性を実装前/非依存に示す」こと
- **trace-checking が最も強い一手** — 実システムの操作ログを採取し、その観測列がモデルの正当な
  振る舞いかを replay で検査する。「実装は naive / atomic どちらの仕様を refine しているか」を
  実データで確定できる

### Step 8 — やめる
限界効用を見て止める。**全部を形式化しない。**

**向くもの**: 全入力/全順序で成り立つべき性質、境界・エッジが多い、並行、クロス境界契約、
「設定ミスが事故になる」もの、信頼境界。

**やめ時**:
- 確率的性質 (期待値・分布) → Z3/TLC 不適合 (整数演算の丸め誤差だけは Z3 可)
- 制御理論的 (PID の収束など) → 忠実モデル化が重く割に合わない
- 既に単体テストで brute-force 済みのアルゴリズム再検証 → spec でなくテストの領分
- 大物を出し切った後の確認的なだけの命題の量産 → CI を重くするだけ
- 主要な不変条件・危険な穴・クロス境界契約を押さえたら、**次は新規形式化より、溜まった反例・
  確認質問をドメインと捌く方がレバレッジが高い**

## 3. anti-pattern

- 直列依存を無理に並行モデル化する
- 実装を読まずに要約・記憶からモデルを組む (偽の証明になる)
- broken-variant を用意せず「緑だから OK」とする (**何も検証していない緑**)
- ネットワーク/手動セットアップに依存した検証 (再現しない)
- 反例を出したまま放置する (台帳 C 欄に確認質問として起票し、決着させる)

## 4. 最終成果物

**証明の山ではなく、`.formal/ledger.md` (実装の主張 / 機械検査の結果 / ドメインへの確認質問) の台帳。**
形式手法はバグを出すためだけでなく、**仕様と認識を揃えるための共通言語**として使う。

台帳が埋まったら次の出口へ渡す:
- 契約 (HOLDS) → `idchain-spec` で SP / TC に固定するか、`run-checks.sh` を CI に入れて回帰ガードにする
- 反例 (REFUTED) → バグなら `proven-done` で修正パイプラインに乗せる。意図なら仕様として明文化する

## ファイル構成

| パス | 役割 |
|---|---|
| `scripts/setup-env.sh` | 検証環境の init / install / check (lockfile 化) |
| `scripts/run-checks.sh` | self-check + broken-variant + 非空を強制する実行ハーネス |
| `templates/model.py` | Z3 モデル雛形 (`refute` / `reachable` ヘルパ付き) |
| `templates/broken_model.py` | 対照の雛形 (ガードを 1 つ外した版) |
| `templates/spec.tla` `.cfg` `.expect` | TLA+ 雛形 (atomic 版、`NeverOverCap` 成立) |
| `templates/broken_spec.tla` `.cfg` | 対照 (read-modify-write に分離して違反する版) |
| `templates/ledger.md` | 台帳テンプレート |
| `reference/bug-catalog.md` | バグ型カタログ (Z-01..05 / T-01..08 / B-01..07) |
| `reference/extraction-questions.md` | 吸い出しの視点と 8 つの問い |
