---
name: idchain-spec
description: idchain の仕様フェーズ (SP 起草 → 形式検査 → G2 人間ゲート → 承認後の TC 導出) を実行する。Use when (1) ユーザーが「仕様を書いて」「SP を起票して」「G2 の承認を通して」と言ったとき、(2) /idchain-spec [SP番号 または SP文] を実行したとき、(3) 承認済み SP からテストケース (TC) を導出したいとき。前提として idchain-init 済みの repo であること。G2 承認の実オペレーションは idchain-approve に委譲し、承認後は idchain-build (TDD 実装) に進む。
---

# idchain-spec

仕様文 (SP) は Lean の型として書き、**形式検査 (`lake build` が通ること) を通らない仕様は
実装に進めない**。テストケース (TC) は「仕様から」導出する — 実装から逆算すると実装追認テスト
になる (発表 p.40)。詳細仕様は `docs/specs/idchain.md`、正例は
`tests/fixtures/idchain-sample/idchain/Canon/*.lean` を参照。

## 前提

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake build && lake exe idchain check  # 現状が green であることを先に確認
```

## 手順

### 1. SP を `Canon/Artifacts.lean` に起草する

- ID 採番規則: **既存 SP の最大番号 + 1**。`retired` 台帳にある番号は再利用禁止
  (`lake exe idchain check` の `retired-identifier-reuse` で機械検出される)。
- SP には**帰属 FA が必須** (`Spec.featureArea : Nat`)。参照する FA が存在しないと
  `spec-without-feature-area` 違反になる。PB/VL/FA がまだ 1 件も無い repo では、
  idchain-discovery skill (G1、上流フェーズ) がまだ存在しないため、最小限の PB/VL/FA を
  ユーザーに確認しながら Canon に追記してからこの手順に戻る。

正例 (`Canon/Artifacts.lean` より、SP-047 を追加したときの形):

```lean
def specs : List Spec := [
  ⟨47, "小計は、明細の合計と常に一致する", 1⟩  -- ⟨番号, 仕様文, 帰属 FA 番号⟩
]
```

### 2. 形式的解釈 (invariant) を追加し、Gate の witness/証明を更新する

同じ `Canon/Artifacts.lean` の状態モデル `Model` と `interpretations` に SP の意味を足す:

```lean
structure Model where
  lineItems : List Nat
  subtotal : Nat

def interpretations : List (SpecInterpretation Model) := [
  ⟨47, fun model => model.subtotal = model.lineItems.sum⟩  -- SP 番号 → invariant
]
```

`Canon/Gate.lean` の `witness` と証明 (`sound`/`complete`) を、**新しい SP を含む全 SP の
invariant を同時に満たす 1 つの witness モデル**が構成できるよう更新する:

```lean
def gate : ConsistencyProof Model registry interpretations := {
  witness := ⟨[1, 2, 3], 6⟩  -- 全 SP の invariant を満たす具体例
  sound := by
    intro interpretation mem
    simp [interpretations] at mem
    subst mem
    rfl
  complete := by decide
}
```

- SP が複数ある場合、`simp [interpretations] at mem` の後に出る場合分けを
  `rcases mem with mem | mem` 等で分割し、各枝を `subst mem; rfl` (または `decide`) で閉じる。
- **これが「形式検査」の実体**: `lake build` が通らない限り `Canon/Gate.lean` (ひいては
  `idchain` exe 自体) がコンパイルできない。矛盾・曖昧さが構造的にゼロになるまで次に進めない。
- 形式化できない (invariant が書けない/証明が閉じない) 仕様文は SP にしてはならない。
  - 曖昧な語彙を削って書き直すか、
  - 前提となる根拠が薄いなら SP 化を見送り、根拠元の PB の `evidence` に
    `Evidence.pending "<何が未確定か>"` を積んで G1 側に差し戻す。
- `decide` が SP 増加で重くなったら `native_decide` に切り替えてよい (fixture の慣例)。

```bash
lake build  # 型検査 + 無矛盾性証明ゲート。ここが exit 0 になるまで先に進まない
```

### 3. トレーサビリティ検査 (この時点では TC はまだ導出しない)

```bash
lake exe idchain check
```

- SP はまだ未承認なので `orphan-spec` (承認済かつ TC 0 件) は発火しない
  (`orphanSpec` は承認済 SP のみ対象)。
- **ここで TC を先に追加してはいけない**: 未承認 SP に TC を紐付けると
  `test-case-for-unapproved-spec` 違反 (G2 承認前の TC 導出は禁止) で exit 1 になる。

### 4. G2 人間ゲート

AskUserQuestion で以下を提示し、承認/却下/修正要求を確認する:

- 仕様文 (SP-XXX の `text`)
- 形式的解釈 (`interpretations` に足した invariant)
- 判断根拠の草稿 (なぜこの文言・この invariant で仕様として確定してよいか)

承認された場合の approve コマンド実行・commit・ハッシュ失効の仕組みは
**idchain-approve** の手順に従う (対象 ID = `SP-<番号>`)。却下/修正要求時の意思の痕跡の
記録方法も同 skill を参照。commit message には `idchain-approve` を含めること
(例: `docs(idchain): approve SP-047 [idchain-approve]`)。

### 5. 承認後: 仕様から TC を導出する

- ID は `TC-<SP番号>-<枝番>` (親 SP 番号を型として保持)。枝番は 1 から。
- **導出元は SP の仕様文と invariant のみ**。実装コード・既存テストを見て逆算することは
  禁止 (実装追認テストを防ぐ)。

```lean
def testCases : List TestCase := [
  ⟨⟨47, 1⟩, "明細3件 → 小計 = 合計", .example⟩,
  ⟨⟨47, 2⟩, "明細0件 → 小計 = 0", .example⟩
]
```

- `TestCaseKind` は `.example` (具体例) / `.property` (性質) / `.oracle` (複数エンジン一致判定、M3) を選ぶ。

```bash
lake build
lake exe idchain check           # orphan-spec が解消していることを確認 (孤児ゼロ)
lake exe idchain views           # Canon の内容が変わったので再生成 (--check ではなく再生成)
lake exe idchain views --check   # 再生成直後の鮮度確認 (差分ゼロになるはず)
```

```bash
git add idchain/Canon/Artifacts.lean idchain/views/
git commit -m "feat(idchain): SP-047 から TC-047-1/2 を導出"
```

## 決定論的ゲートの実行順序 (このフェーズで必須)

```
lake build  →  lake exe idchain check  →  lake exe idchain views --check
```

この順序を崩さない (証明が閉じていない状態でトレーサビリティ検査をしても無意味、
トレーサビリティが破れた状態でビューを再生成しても正本と一致しない)。

## 次のフェーズへ

- G2 承認済み・TC 導出済み・check が green になったら **idchain-build** で TDD 実装に進む。
- G2 の承認/却下オペレーションそのものは **idchain-approve** を使う。
