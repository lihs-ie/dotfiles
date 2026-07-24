---
name: idchain-approve
description: idchain の人間ゲート (G1/G2/G3 共通) の承認オペレーションを実行する。対象 ID の現内容提示 → 承認/却下/修正要求の確認 → approve コマンド実行 → 再ビルド・再検査 → commit までを行う。Use when (1) ユーザーが「承認して」「SP-047 を承認」「却下したい」と言ったとき、(2) /idchain-approve <ID> を実行したとき、(3) idchain-spec の G2 手順や将来の G1/G3 手順から承認オペレーションを委譲されたとき。この skill は承認の「実オペレーション」専用で、SP の起草自体は idchain-spec、実装は idchain-build を使う。
---

# idchain-approve

承認は Lean 正本 (`Canon/Approvals.lean`) に埋め込み、**対象アーティファクトの内容の
正準直列化 + FNV-1a 64bit ハッシュに束縛**される。書込は `lake exe idchain approve` 経由のみで、
真正性は git 履歴が担保する。この skill は PB/VL/FA/HY/SP/LL のどの対象にも共通で使う。

## 手順

### 1. 対象 ID の現内容を提示する

正本 (`Canon/Artifacts.lean`) から対象 ID の該当エントリを直接読んで提示する。
`views/*.md` は生成物 (鮮度がずれている可能性がある) なので現内容確認の一次情報源にしない。

```bash
cd <対象repo>/idchain
grep -n "⟨47" Canon/Artifacts.lean   # 例: SP-047 の該当行を探す (kind ごとにリストが分かれている)
lake exe idchain check               # 既存承認がある場合、失効していないかも同時に見える
```

- 既に承認済みで再承認 (修正後の再提出) の場合は、`check` の `stale-approval` 有無で
  現在の承認状態 (有効/失効) を確認する。

### 2. 承認/却下/修正要求を確認する

AskUserQuestion で提示する:

- 対象 ID とその現内容 (仕様文・invariant・判断根拠の草稿など、呼び出し元 skill が用意したもの)
- 選択肢: 承認 / 却下 / 修正要求
- 承認する場合は「承認者名」「判断根拠 (note)」を追加で確認する

### 3a. 承認する場合

**必ず `idchain/` (Canon/ を含むディレクトリ) から実行する** — `approve` コマンドは
cwd 相対で `Canon/` の存在を確認するため、ここを外すと exit 2 になる。

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake exe idchain approve <ID> --by <承認者> --note <判断根拠> --date <YYYY-MM-DD>
```

- 引数の**順序は固定**: `<ID> --by <承認者> --note <判断根拠> --date <YYYY-MM-DD>`。
  順序を変えたり過不足があると usage エラー (exit 2) になる。
- `<ID>` は `SP-047` のようなゼロ埋め表記 (`SimpleIdentifier.parse` は render の像のみ受理、
  `SP-47` は不正扱い)。
- 成功すると `Canon/Approvals.lean` が**全量再生成**される (既存の同一対象への承認は
  upsert = 置換される。再承認もこのコマンド 1 本でよい)。手編集は禁止。

承認後は再ビルド・再検査してから commit する:

```bash
lake build
lake exe idchain check
```

```bash
git add idchain/Canon/Approvals.lean
git commit -m "docs(idchain): approve <ID> [idchain-approve]"
```

- commit message に `idchain-approve` を含めること。CI テンプレート
  (`.github/workflows/idchain.yml`) はこのトークンが無いまま `Approvals.lean` が変更されると
  警告を出す (承認の真正性を git 履歴で担保する仕組みの一部)。

### 3b. 却下・修正要求の場合

**`approve` コマンドを実行しない** (=`Approvals.lean` には一切書き込まない)。
「意思の痕跡」(何を・なぜ棄てたか) は正本のデータ構造にある範囲で記録する:

- 対象が **PB (Problem)** かつ却下理由が「根拠不足」の場合:
  `Canon/Artifacts.lean` の該当 `Problem.evidence` に `Evidence.pending "<何が未確定か>"` を
  追記する (型付き未充足フィールドとしてゲートで見える化する)。
- 対象が **VL/FA/HY/SP/LL** の場合、これらの型には汎用の note フィールドが無いため、
  却下理由と次アクションは commit メッセージ本文に残す (Approvals.lean は変更しない):

```bash
git commit -m "$(cat <<'EOF'
docs(idchain): <ID> を G2 で却下 (書き直し)

却下理由: <判断根拠>
次のアクション: 仕様文/invariant を書き直して再度レビューを申請
EOF
)" --allow-empty
```

- 修正要求の場合は、依頼元の skill (多くは idchain-spec) の手順に戻って本文/invariant を
  書き直し、この skill の手順 1 からやり直す。

## ハッシュ束縛と失効

- 承認は対象内容の**正準直列化 + FNV-1a 64bit ハッシュ**に束縛される
  (`Approval.contentHash`)。ハッシュ自体はセキュリティ目的ではなく、内容変更の決定論的検出が目的。
- 承認**後**に対象アーティファクト (例: SP の text や featureArea) を編集すると、
  現内容のハッシュと承認時のハッシュが不一致になり、`lake exe idchain check` が
  `stale-approval` 違反 (「承認後に内容が変更されている。承認は失効。再承認が必要」) を
  exit 1 で報告する。
- 失効した承認は**再びこの skill の手順 3a**で再承認する (`approve` コマンドは同一対象への
  再実行で自動的に古い承認を置換する)。失効した承認のまま次のフェーズ (TC 導出・実装) に
  進んではならない。

## 呼び出し元との関係

- G2 (仕様承認): **idchain-spec** から呼ばれる。対象は `SP-<番号>`。
- G1/G3 (Why/What 確定・成果レビュー): 対応する discovery/retro skill (未実装、M2 スコープ) が
  将来この skill を同様に呼ぶ想定。現時点では対象 ID を明示して直接この skill を呼んでもよい。
- 承認後の実装着手は **idchain-build** へ。
