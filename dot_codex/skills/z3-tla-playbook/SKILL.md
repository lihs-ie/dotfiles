---
name: z3-tla-playbook
description: 既存実装を事実上の仕様として読み、Z3・TLA+・有限全列挙から最小の手段を選んで、設定矛盾、被覆漏れ、表現ずれ、並行レースなどの反例を探索する独立デバッグ Skill。Use when ユーザーが「形式手法で検証」「Z3 で検査」「TLA+ でモデル検査」「反例を出して」「実装から仕様を吸い出して」「並行バグを洗い出して」「設定が矛盾していないか」「不変条件を検査して」と依頼したとき、または $z3-tla-playbook を実行したとき。結果を HOLDS / REFUTED / ERROR に分け、モデル・反例・判断記録を .formal/ に残す。仕様承認、実装修正、他の開発フローへの引き渡しは行わない。
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
> <https://gist.github.com/mizchi/db7817e6fc077d567c41cd9d41bb1c53>
> revision `2133eced8334ed36e47ec4d6e138a46552539256`。
> 本 Skill は上記方法論をローカルの実行ハーネスと台帳運用に落とし込んだ実行可能な正本である。
> 通常実行時に gist や git へアクセスしない。必要な本文・雛形・参照資料はこのパッケージに同梱する。

## 責務と非責務

| この Skill が行う | この Skill が行わない |
|---|---|
| 実装と実データを読んで検査対象を抽出する | 仕様を承認・確定する |
| 最小の検査手段を選び、モデルと対照を作る | 本番コードを修正する |
| 検査を実行し HOLDS / REFUTED / ERROR に分類する | 他 Skill や開発パイプラインへ結果を引き渡す |
| `.formal/` にモデル・反例・台帳を残す | `.formal/` 外へ成果物を生成する |

**独立性の境界:** 他 Skill の正本、承認、ID、成果物を読んだり更新したりしない。結果の解釈と次の行動は
ユーザーが別途決める。この Skill の完了は「デバッグ結果が再実行可能な形で `.formal/` に残ったこと」であり、
修正や仕様化まで進んだことではない。

## 完了条件と結果の語彙

- `HOLDS`: 指定した有限モデル・制約の範囲では性質が破れなかった。コード全体の正しさを意味しない。
- `REFUTED`: 具体的な witness または TLC trace があり、主張を破る実行が見つかった。
- `ERROR`: 依存不足、構文エラー、タイムアウト、クラッシュなど。`REFUTED` として扱わない。
- 個々の主張の結果と、モデル process の self-check exit を混同しない。process は「宣言した期待結果との一致」を
  検査し、全て一致なら exit 0、不一致なら exit 1、solver unknown / 実行 ERROR なら exit 2 以上を返す。
  したがって、期待 `REFUTED` の主張から実際に反例が出たモデルは exit 0 で正しい。
- 基準モデルと broken variant の両方を同一ハーネスで実行する。
- `.formal/ledger.md` に対象 commit、file:line、モデル範囲、結果、witness、model↔code gap、再実行コマンドを残す。
- 最終報告は `.formal/` 内の成果物、三値結果、残る gap を示す。バグ修正や仕様化を勝手に開始しない。

## 0. 環境

明示された `SKILL.md` のパスからパッケージディレクトリを確定する。明示パスが無い通常利用時だけ
インストール先を使う。chezmoi source checkout では実行属性を `executable_` 接頭辞で表すため、
配布後名と source 名のどちらか一方だけが存在する。

```bash
SKILL="${Z3_TLA_SKILL_DIR:-$HOME/.codex/skills/z3-tla-playbook}"
if [ -x "$SKILL/scripts/setup-env.sh" ]; then
  SETUP="$SKILL/scripts/setup-env.sh"
  RUN_CHECKS="$SKILL/scripts/run-checks.sh"
elif [ -x "$SKILL/scripts/executable_setup-env.sh" ]; then
  SETUP="$SKILL/scripts/executable_setup-env.sh"
  RUN_CHECKS="$SKILL/scripts/executable_run-checks.sh"
else
  echo "z3-tla-playbook scripts not found under: $SKILL" >&2
  exit 2
fi

bash "$SETUP" --dir .formal --init       # 検証ディレクトリと雛形
bash "$SETUP" --dir .formal --install    # z3-solver + tla2tools.jar
bash "$SETUP" --dir .formal --check      # lock と実環境の照合
```

Skill を絶対パスで渡された評価・開発時は、先にその親ディレクトリを設定する。

```bash
export Z3_TLA_SKILL_DIR="/absolute/path/to/z3-tla-playbook"
```

`.formal/formal-lock.json` に**実際に入った版**を記録する (推測値を書かない)。
`.venv/` と `tools/` は commit しない — lock だけが版の正本。

## 1. ツールの使い分け

| 手段 | 選択条件 | 問い | 主な成果物 |
|---|---|---|---|
| 全列挙 | 入力と遷移が有限かつ決定的 | 列挙した全ケースで成り立つか | `.formal/models/*.py` と witness |
| Z3 (SMT) | 区間・集合・等式などの純粋述語 | **全入力に対して、ある一瞬** | `.formal/models/*.py` と solver model |
| TLA+ (TLC) | 状態遷移・並行・非決定性が本質 | **時間を通じて、全順序・全 interleaving** | `.formal/specs/*` と TLC trace |

**判定フロー（この順番を変えない）:**

- 有限かつ決定的なら **全列挙**。Z3/TLA+ を使わない判断も成果であり、理由を ledger に書く。
- それ以外で「この条件、**どんな入力でも**成り立つ?」「この設定、**配信され得る**?」
  → 述語が区間 + 集合 + 等式の decidable fragment なら **Z3**
- 「**どの順番で起きても**大丈夫?」「同時に来たら?」「クラッシュ後は?」「いつか必ず〜する?」
  → 状態遷移 + 非決定性 → **TLA+**
- 選べない場合はモデルを書き始めず、対象入力、状態、時間依存、検査したい主張をユーザーに確認する。

## 2. 1 周のワークフロー

### Step 1 — 対象と停止範囲を固定する
`reference/bug-catalog.md` で「ありそうな型」を 2〜3 個当てる。当てずに全部を形式化しない。
対象ファイル、対象 commit、入力領域、検査する性質、今回は扱わない領域を ledger に先に書く。

### Step 2 — 実装を読んで吸い出す
`reference/extraction-questions.md` の 8 つの問いを**機械的に**投げる。
「宣言された仕様」と「暗黙の挙動」を分けて `.formal/ledger.md` の A 欄に **file:line 付き**で記録する。

**実装を読まずに要約・記憶からモデルを組まない。** 変換テーブルを 1 つ取り違えると偽の証明になる。

### Step 3 — 手段を選び、決定関数と invariant を書く
- 前節の順番で全列挙 / Z3 / TLA+ を選び、理由を ledger に書く
- 配管 (I/O・フレームワーク・DB) を剥がした純粋関数 `predict(state)` として書く
- 証明したい性質に**名前を付ける** (`NeverOverCap == served <= cap`)
- **成立を証明したいのか、反例が欲しいのか**を決めてから invariant を立てる
- 境界 (`cap-1`, `cap`, `cap+1`) と空集合を定義域に必ず入れる

雛形: `.formal/models/example_cap.py` (Z3) / `.formal/specs/Example.tla` (TLA+)。

### Step 4 — 回す
```bash
bash "$RUN_CHECKS" --dir .formal
```
このハーネスは 3 つを同時に強制する:
1. **self-check** — 各モデルが期待判定 (HOLDS/REFUTED, OK/VIOLATE) と一致するか
2. **broken-variant** — わざと壊した変種が**赤で捕まる**か。捕まらなければその検査は何も守っていない
3. **空でないこと** — モデル 0 件の「空っぽの緑」を失格にする

`.formal/models/broken/<stem>__<label>.py` と `.formal/specs/broken/<Stem>__<Label>.tla`
に対照を置く。**対照が無いモデルは失格になる** (`--allow-missing-broken` で一時回避可)。

**モデル process の self-check exit code 契約** — 個々の主張の三値分類とは別に、自作モデルはこれに従うこと:

| exit | 意味 |
|---|---|
| 0 | 全主張が宣言した期待結果と一致。期待 `REFUTED` と実際 `REFUTED` の一致も含む |
| 1 | 期待結果との不一致。broken variant はこの exit を期待する |
| 2 以上 | ERROR (依存不足・solver unknown・モデル自体の不備・クラッシュ)。**反例ではない** |

対照は **exit 1 でのみ「捕まった」と認める**。exit 2 以上は異常終了として失格にする —
venv 破損や import 失敗を「壊れた実装を検出できた」と数えないため。
TLA+ 側も同様に、TLC の非 0 exit を VIOLATE と ERROR に分類する。

### Step 5 — 結果を台帳に落とす
- **REFUTED** → witness または trace を `.formal/` に保存し、「これは意図か?」を台帳 C 欄に書く
- **HOLDS** → 有限化・抽象化・前提を台帳 B/D 欄に書き、回帰検査として残す
- **ERROR** → 検査結果に数えず、コマンド、exit code、標準エラー、再試行条件を台帳 D 欄に書く

両方揃うと「何が保証され / 何が穴か」の台帳になる。

### Step 6 — 再実行可能性を確認する
`run-checks.sh` は人間可読な出力と機械可読な exit code を両方出す。環境を `--check` し、
ledger の再実行コマンドをそのまま実行して同じ分類になることを確認する。CI への組み込みはユーザーが
明示的に依頼した場合だけ行い、その場合もローカルと CI は**同一のハーネスを叩く**。

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
- 主要な不変条件・危険な穴・クロス境界契約を押さえたら、新規形式化を止めて結果を報告する

## 3. anti-pattern

- 直列依存を無理に並行モデル化する
- 実装を読まずに要約・記憶からモデルを組む (偽の証明になる)
- broken-variant を用意せず「緑だから OK」とする (**何も検証していない緑**)
- 通常検査時にネットワーク取得する（依存導入は明示的な `--install` に限定する）
- 反例を出したまま放置する (台帳 C 欄に確認質問として起票し、決着させる)

## 4. 最終成果物

**証明の山ではなく、`.formal/ledger.md` (実装の主張 / 機械検査の結果 / ドメインへの確認質問) の台帳。**
形式手法はバグを出すためだけでなく、**仕様と認識を揃えるための共通言語**として使う。

台帳が埋まり、同じコマンドで再実行できたら結果をユーザーへ報告して停止する。後続の仕様化、修正、
CI 組み込みはこの Skill の責務に含めない。

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
