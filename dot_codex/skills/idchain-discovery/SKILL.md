---
name: idchain-discovery
description: idchain のディスカバリーフェーズ (ダブルダイヤモンドで課題→価値→仮説を発散収束させ、Why/What 一式 PB/VL/FA/HY を確定して G1 人間ゲートを通す) を実行する。Use when (1) ユーザーが「ディスカバリーをやりたい」「課題を洗い出したい」「Why/What を固めたい」「G1 の承認を通して」と言ったとき、(2) $idchain-discovery [課題領域] を実行したとき、(3) idchain-retro の学びを受けて次の仮説を検討し直すとき。前提として idchain-init 済みの repo であること。G1 承認の実オペレーションは idchain-approve に委譲し、確定後は idchain-spec (SP 起票) に進む。
---

# idchain-discovery

Why/What (PB/VL/FA/HY) は独立した成果物として先に固める (発表 p.66)。AI の役割は
「文書生成器」ではなく「熟練インタビュアー」— テンプレを勝手に埋めて結論ありきの文書を
作ってはならない (発表 p.67)。人が意思を持ち、AI は引き出し・構造化し・根拠をもって
反論する (発表 p.69)。詳細仕様は `docs/specs/idchain.md` の Must-16、正例は
`tests/fixtures/idchain-sample/idchain/Canon/Artifacts.lean` の
Problem/Value/FeatureArea/Hypothesis を参照。

## 前提

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake build && lake exe idchain check  # 現状が green であることを先に確認
```

- PB/VL/FA/HY が 1 件も無い初回起動でも、空リストは違反にならないので green で通る。

## 手順

### 1. 問題空間: ダブルダイヤモンド 1周目 (課題候補を広げてから絞る)

- **発散**: ユーザーに課題候補をできるだけ広く出してもらう。AI がテンプレの空欄を
  勝手な推測で埋めることを最大の禁止事項とする (発表 p.67「AI にテンプレを埋めさせると、
  結論ありきの文書ができあがる」)。わからない・決めていない所は次の手順4のとおり
  pending のまま残す。
- **収束**: 出た候補を構造化する (重複整理・矛盾抽出・根拠の有無仕分け) のは AI の役割。
  「どれを解くべき課題とするか」の決定はユーザーが行う。AI は納得ずくで鵜呑みにせず、
  根拠をもって反論してよい (例:「この課題は先の発言と矛盾しないか」)。
- 棄却した課題候補は消さず、次の手順3で記録する。

### 2. 解空間: ダブルダイヤモンド 2周目 (解決策候補を広げてから絞る)

- 解くべき課題が定まったら、それに対する価値仮説・機能領域の候補を同じ手順
  (広げる→絞る) で扱う。役割分担 (人=意思、AI=構造化+反論) は問題空間と同じ。
- 2 回の発散収束を経て初めて「価値のある仕様」の手前が固まる (発表 p.68「正しい課題
  なしに、正しい解はない」)。1 周目を飛ばして解決策から入ってはならない。

### 3. 意思の痕跡を記録する

「検討したが選ばなかった案」「なぜこの案を選んだか」の記録がない成果物は不完全として
扱う (発表 p.69 原則②)。記録先:

| 内容 | 記録先 |
|---|---|
| 採用案の判断根拠 | 各アーティファクトを承認する際の `--note` (手順7、idchain-approve 手順) |
| 棄却案・検討過程 | 当該 PB の `evidence` に `.recorded "検討した代替案" "棄却理由: ..."` として追加、または起草 commit の本文 |

### 4. わからない所は埋めない

確度の低い前提は `Evidence.pending "<何が未確定か>"` として空欄のまま可視化する
(発表 p.69 原則③)。埋まるまでゲートを通さない — 憶測で `.recorded` に書き換えない。

```lean
def problems : List Problem := [
  ⟨2, "大規模データのお客様で最頻画面の表示が遅い", [.pending "遅いと感じる具体的な操作の特定"]⟩
]
```

### 5. 仮説を反証可能形式で起票し、検証順序をつける

- HY は観測可能な指標+閾値で書く。✗「使ってくれるはず」→ ✓「週1回以上使われる」
  (発表 p.72 原則①、気持ちを主語にしない)。
- `importance` (重要度、1-5) × `evidenceStrength` (証拠の強さ、1-5) で並べ、
  **重要度が高く証拠の弱い仮説から検証する** (発表 p.72 原則②「一番危ない仮説から試す」)。
- 検証はいきなり実装しない。「つくらずに検証する打席」を優先し、そこで筋が良いと
  判った仮説だけを idchain-spec の実装サイクルに乗せる (発表 p.70「打席数はディスカ
  バリーで稼ぎ、当たりは一周で確かめる」)。打席の種類は以下の 2 系統:

  | 打席の種類 | 内容 | 目的 |
  |---|---|---|
  | ディスカバリーの打席 | 机上リサーチ / インタビュー / プロトタイプ (数時間〜数日) | 仮説の外れを安く早く潰す |
  | 一周まわす打席 | 探索→仕様→実装→検証→リリース→学び (idchain の全フェーズ) | 筋の良い仮説だけを実サイクルで確かめる |

- 確からしさは反証耐性で測る — 都合の良い証拠だけを数えず、反証を試みた回数を
  判断根拠のメモに残す (発表 p.72 原則③)。

### 6. Canon/Artifacts.lean に PB → VL → FA → HY を起草する

採番規則: **種別ごとに既存最大番号 + 1**。VL は PB とペア必須、FA は対応 VL 必須、
HY は対応 PB 必須 (`hypothesis-without-anchor` 違反で機械検出される)。

```lean
def problems : List Problem := [
  ⟨2, "<課題文>", [.recorded "<根拠トピック>" "<出典>"]⟩
]

def values : List Value := [
  ⟨2, "<価値文>", 2, "<合格ライン>"⟩  -- ⟨番号, 文, 対応PB番号, 合格ライン⟩
]

def featureAreas : List FeatureArea := [
  ⟨2, "<機能領域名>", [2]⟩  -- ⟨番号, 名前, 対応VL番号列⟩
]

def hypotheses : List Hypothesis := [
  ⟨2, "<観測可能な仮説文>", "<指標>", "<閾値>", 4, 2, [2], .untested⟩
  -- ⟨番号, 文, 指標, 閾値, 重要度, 証拠の強さ, 対応PB番号列, 状態⟩
]
```

```bash
lake build
lake exe idchain check
```

- `value-without-problem` / `feature-area-without-value` / `hypothesis-without-anchor`
  が 0 件になるまで対応関係を直す。

### 7. G1 人間ゲート

ユーザーに以下を提示し、確定/差し戻しを確認する。提示するのは Canon の
現内容そのもの (`views/*.md` は生成物なので鮮度がずれる可能性があり一次情報源にしない)。

- 課題文 (`PB-XXX` の `statement`) と根拠 (`evidence`、pending が残っていればそれも明示)
- 価値文 (`VL-XXX`) と合格ライン (`successCriterion`)
- 機能領域 (`FA-XXX`) と対応する価値
- 仮説 (`HY-XXX`) の指標・閾値・重要度×証拠の強さと検証順序の草稿
- 選択肢: 確定 / 一部差し戻し (どの ID を、どう直すか) / 全面差し戻し

承認された対象 (PB/VL/FA/HY それぞれ) は **idchain-approve** の手順3aに従って
1 件ずつ `lake exe idchain approve [ID] --by <承認者> --note <判断根拠> --date <YYYY-MM-DD>`
を実行する (approve コマンドは 1 呼び出しにつき 1 ID)。`Canon/Approvals.lean` への
反映はまとめて 1 commit でよい (commit message に `idchain-approve` を含める)。
差し戻し・修正要求の場合は idchain-approve の手順3bに従う (意思の痕跡として理由を残す)。

### 8. 確定した Why/What からロードマップ項目 (RM) を起票する

「筋の良いと判った仮説だけを一周に乗せる」(手順5、発表 p.70) の具体化。G1 で承認された
HY のうち、机上検証だけに留めず**一周まわす打席** (探索→仕様→実装→検証→リリース→学び、
idchain の全フェーズ) に乗せると判断したものについて、`Canon/Artifacts.lean` の
`roadmapItems` に RM を追記する。まだ承認されていない、あるいは机上検証に留める HY には
起票しない。

採番規則: **既存 RM の最大番号 + 1** (欠番禁止、`roadmap-not-contiguous` 検査対象)。

```lean
def roadmapItems : List RoadmapItem := [
  ⟨1, "集計エンジンの汎用化", .planned, 1, some 1, "discovery"⟩,
  ⟨2, "<HY-XXX を一周に乗せた際の題名>", .planned, <優先度>, some 2, "discovery"⟩
  -- ⟨番号, 題名, 状態, 優先度, 関連HY番号, 出典⟩
]
```

- `status` は起票時点では常に `.planned`。次サイクルでの着手を確定する `.inCycle` への
  遷移には承認が必要 (idchain-approve、対象 `RM-<番号>`) — 判断が固まっていないうちに
  `.inCycle` にしない。
- `priority` は `importance × evidenceStrength` (手順5 で決めた重要度×証拠の強さ) を目安に、
  値が大きい (重要度が高く証拠が強い) HY ほど小さい数値 (=次に潰す順) を割り当てる。既存 RM
  との相対順位で決めてよい (絶対値の計算式は決定論検査の対象外)。この判断根拠は起票時の
  commit message か、承認する場合は approve の `--note` に残す。
- `hypothesis` は対応 HY 番号 (`some N`)。存在しない HY を指すと `roadmap-hypothesis-missing`
  違反になる。
- `source` は `"discovery"` を使う (HY 起票と同じフェーズ由来のため)。

```bash
lake build
lake exe idchain check   # roadmap-hypothesis-missing / roadmap-not-contiguous が0件であることを確認
```

## 決定論的ゲートの実行順序 (このフェーズで必須)

```
lake build  →  lake exe idchain check  →  lake exe idchain views --check
```

## 次のフェーズへ

```bash
lake exe idchain views
lake exe idchain views --check
```

```bash
git add idchain/Canon/Artifacts.lean idchain/Canon/Approvals.lean idchain/views/
git commit -m "docs(idchain): approve PB-002/VL-002/FA-002/HY-002 [idchain-approve]"
```

- G1 承認済みになったら **idchain-spec** で SP 起票へ進む。
- ライフサイクル全体: **idchain-discovery (本 skill) → idchain-spec → idchain-build →
  idchain-retro** → (学びをもとに次に潰す仮説を見直して) **idchain-discovery へ戻る**
  (発表 p.64「ライフサイクル全体を一本の鎖に」、p.73「学びが、次の打席を書き換える」)。
