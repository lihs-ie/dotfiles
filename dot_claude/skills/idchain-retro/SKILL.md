---
name: idchain-retro
description: idchain のリリース後の成果レビュー (先に固定した合格ライン vs 実測値の判定、HY の status 更新、LL 追記、G3 人間ゲート、ロードマップ書き換え) を実行する。Use when (1) ユーザーが「成果レビューをやりたい」「リリース後の振り返り」「学びを台帳に残したい」「G3 の承認を通して」と言ったとき、(2) /idchain-retro [SP番号 または HY番号] を実行したとき、(3) idchain-build の実装・検証レポート PASS 後にリリースが完了し、成果を判定するとき。前提として対象 SP/HY が承認済みで検証レポートが存在すること。G3 承認の実オペレーションは idchain-approve に委譲し、学びを踏まえた次の一手は idchain-discovery または idchain-spec に戻る。
---

# idchain-retro

トレーサビリティの鎖はリリースの先まで続く (発表 p.63「後ろへ => 価値は出たのか」)。
出して終わりにせず、**先に決めた合格ラインで判定し、学びを台帳へ記録し、ロードマップを
書き換える** (発表 p.73)。詳細仕様は `docs/specs/idchain.md` の Must-17、正例は
`tests/fixtures/idchain-sample/idchain/Canon/Artifacts.lean` の Hypothesis/Learning を参照。

## 前提

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake build && lake exe idchain check  # 現状が green であることを先に確認
```

- 対象 VL/HY が G1 で承認済みであること、対象 SP が idchain-build で検証レポート
  PASS まで到達していることを前提とする。未達なら idchain-spec / idchain-build に戻る。

## 手順

### 1. 先に固定した合格ラインで判定する

対象の合格ラインを **Canon から直接**提示する (`views/*.md` は生成物なので鮮度が
ずれる可能性があり一次情報源にしない):

```bash
grep -n "⟨2" Canon/Artifacts.lean   # 対象 VL-002 / HY-002 相当の行を探す
```

- 提示するのは `Value.successCriterion` (合格ライン) と `Hypothesis.threshold`
  (仮説の閾値) — どちらも G1 で固定済みの数値・条件。
- **合格ラインの後出し変更は禁止**。実測値を見てから `successCriterion` /
  `threshold` の文言そのものを書き換えることは、合格ラインを結果に合わせて
  動かす行為であり許されない。書き換えると `Value`/`Hypothesis` の内容ハッシュが
  変わり、`lake exe idchain check` が `stale-approval` (承認後に内容が変更されている)
  として検出する。合格ラインの見直しが本当に必要なら、既存 VL/HY を書き換えず
  **idchain-discovery に戻って新しい HY として起票**し、あらためて G1 で承認する。
- AskUserQuestion または対話で実測値をユーザーから収集する (計測方法・計測期間も
  合わせて確認し、次の LL に残せるようにする)。

### 2. HY の status を更新する

実測値と閾値を比較し、`Hypothesis.status` を `.untested` から `.supported`
(閾値を満たした) または `.refuted` (満たさなかった) に更新する。
**反証された仮説も削除しない** (発表 p.73「外れた仮説も、消さずに記録」)。

```lean
⟨2, "<仮説文>", "<指標>", "<閾値>", 4, 2, [2], .refuted⟩  -- .untested → .supported/.refuted
```

- `status` は内容ハッシュの一部なので、G1 で承認済みの HY はこの変更で
  `stale-approval` になる。これは想定内の挙動 (状態確定は成果レビューの結果
  そのもの) — 手順5の G3 承認でこの HY もあわせて再承認する。

### 3. LL を追記する

- 番号は **既存 LL の最大番号 + 1**。1..N の連番を厳守し、欠番を作らない
  (`learning-not-contiguous` 検査が機械的に縛る)。**LL は削除禁止** — append-only。
- 外れた仮説 (`.refuted`) の学びも必ず記録する。何が違ったか・次にどう活かすかを
  `outcome` に書く。
- `date` は成果レビューを行った日 (計測日ではなく判定日)。

```lean
def learnings : List Learning := [
  ⟨1, "2026-07-24", some 1, "初回計測は仮説を支持"⟩,
  ⟨2, "2026-07-24", some 2, "<結果と学びの要約>"⟩  -- hypothesis は Option HY番号、対象がなければ none
]
```

```bash
lake build
lake exe idchain check   # learning-not-contiguous が0件、対象HYの承認状態を確認
```

### 4. append-only の履歴検査 (LL の削除・書き換えが無いことを確認する)

スナップショット検査 (`lake exe idchain check` の `learning-not-contiguous`) は
**連番の充足のみ**を保証し、過去エントリの書き換えは検出できない。履歴改変の検出は
git に委ねる — この役割分担を踏まえ、必ず以下を実行する:

```bash
cd <対象repo>
git log -p -- idchain/Canon/Artifacts.lean
```

- 出力中の `def learnings : List Learning := [ ... ]` 部分に着目し、過去の commit で
  既存のエントリ行が **削除 (`-` 行) または内容の書き換え** (同じ LL 番号の行が
  `-` と `+` の両方に別内容で現れる) をされていないかを目視で確認する。追加
  (`+` 行のみ) であれば append-only 性が保たれている。削除・書き換えを見つけた
  場合は履歴改変であり、この skill の手順を続行せずユーザーにエスカレーションする。

### 5. G3 人間ゲート

AskUserQuestion で以下を提示し、成果判定を確定する:

- 対象 VL/HY の合格ライン (手順1で提示したもの) と実測値
- 判定結果案: 合格 / 不合格 / 部分合格 (どの観点が合格でどこが未達か)
- 追記した LL の内容 (`outcome`)

確定したら、追記 LL と手順2で status を更新した HY を **idchain-approve** の手順3aで
承認する (対象ごとに 1 回ずつ `lake exe idchain approve <ID> --by <承認者> --note
<判断根拠> --date <YYYY-MM-DD>` を実行、`Approvals.lean` への反映はまとめて
1 commit でよい)。判定が「不合格」でも LL 自体は承認する (学びの記録は判定結果に
関わらず必要)。

### 6. ロードマップを書き換える

学びに基づき「次に潰す仮説」を更新する (発表 p.73「学びが、次の打席を書き換える」):

- 新しい HY を起票する、または既存 HY の `importance`/`evidenceStrength` を
  見直す。これらは idchain-discovery の手順6と同じ起草手順で行う。
- **`importance`/`evidenceStrength` を変更した HY は内容ハッシュが変わるため、
  承認済みなら再承認が必要**になる (idchain-approve、対象は変更した HY)。
  変更したままゲートを通さずに次フェーズへ進めない。
- 次の一手が新しい課題領域なら **idchain-discovery** (問題空間から) に、
  既存の Why/What の範囲内で仕様を追加するだけなら **idchain-spec** に戻る。

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
git commit -m "docs(idchain): approve LL-002 / HY-002 成果レビュー [idchain-approve]"
```

- ライフサイクル全体: idchain-discovery → idchain-spec → idchain-build →
  **idchain-retro (本 skill)** → (学びをもとに) idchain-discovery または
  idchain-spec に戻る (発表 p.64、p.73)。
