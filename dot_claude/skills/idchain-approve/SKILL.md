---
name: idchain-approve
description: idchain の直接承認と、固定スコープ契約に基づく委任判断を記録する。G1/G2/G3、再承認、または確認を最小限にした一気通貫実行の権限判定で使う。委任はゴール変更や外部操作権限を含まない。SP起草自体はidchain-specを使う。
---

# idchain-approve

## 委任実行

委任は「固定成果を達成する手段」に限り、ゴールを追加・緩和する権限ではない。
対象repoのvendored engineに委任CLIがあることを確認する。Skillの更新だけで旧engineに機能が増えたとは扱わず、
未導入ならその差分を一度説明する。別repoへのengine上書きや既存のより厳しい規則の削除を自動実行しない。
ユーザーが代理判断を明示した場合は、次を1つの契約にまとめる。既に同内容の委任があるなら
同じ質問を繰り返さない。委任がない場合は以下の通常承認手順を使う。

- 利用者に見える終了状態、識別可能な受入条件、対象外、停止条件
- 固定対象IDと受入条件の対応、許される判断、変更可能な範囲
- 準備・独立レビュー・判断の有限累積予算、終了時に必要な実検証証拠
- 元のユーザー指示、委任者、実行エージェント。外部公開・費用・削除等は別の操作権限

契約内容を人間が確定した証拠を持って初めてgrantを登録する。「自走して」という文だけを根拠に
AIが後から作った契約の全条件を人間承認済みとしない。未確定事項が成果に影響する場合は一度にまとめて確認する。
同じ契約を再質問しない一方、契約本文・受入条件・対象ID・予算の変更を代理承認しない。

### CLIと保存先

対象repoの`idchain/`から実行する。JSONの正確な型はvendored engineの`Idchain/Delegation.lean`を読む。
`DelegationContract`には`identifier / outcome / criteria / nonGoals / targets / anchors / agents / decisions /
preparationBudget / reviewBudget / decisionBudget / stopConditions`を入れる。
`targets`は`target`と`criterion`の組、`anchors`は人間承認済みの上流IDと内容hashの組とする。
対象番号を予約しておけば、後続仕様の本文は範囲内で具体化できる。上流成果の変更を同じ契約へ混ぜない。

```bash
lake exe idchain delegation inspect contract.json
lake exe idchain delegation grant contract.json --by <実際の委任者> --note <元の承認根拠> --date <日付> --confirm-hash <inspectで提示したhash>
git add .delegation/contracts/
git commit -m "docs(idchain): record bounded delegation [idchain-approve]"
lake exe idchain delegation use request.json
lake build
lake exe idchain check
git add .delegation/ledger.json Canon/Approvals.lean
git commit -m "docs(idchain): record delegated decision [idchain-approve]"
```

`grant`は契約の確定内容に対する人間承認がある場合だけ実行する。初版はrepo内の契約を1件に限定し、
別名での再grantによる予算リセットを拒否する。新しい契約への更新手順は未提供なので、台帳を削除して再開始しない。
`.delegation/`はCanonと同じ`idchain/`配下に保存する。各判断は次の判断前にcommitし、契約・台帳・証拠の差替えをしない。
台帳への書込は統括担当が直列に行う。別担当のレビューは並行できるが、複数プロセスから`use`を同時実行しない。

`DelegationUse`の`sequence / contract / contractHash / agent / decision / target / criterion / date / note`を指定する。
判断種別は`prepare / review / approve / complete`。承認は`contentHash`と独立scope reviewの証拠を添える。
レビュー開始前に、実際に割り当てた別担当を`agent`とした`review`を対象hashへ予約・commitする。
契約の`agents`には実行担当とレビュー担当を含める。scope receiptの`reviewedBy`は予約した担当と一致させる。
予約を結果として扱わず、担当の実レビュー後にreceiptを記録する。失敗しても予約の消費を消さない。
証拠は`path / hash`の組で、pathは`idchain/`からの相対パス、hashは`git hash-object --no-filters`の値。
証拠ファイルは判断前にGitへ固定する。`complete`には全criterionと実検証reportを結合したcompletion証拠を添える。
`approve`の`evidence[0]`はscope receipt。LL・doneのRM・判定済みHYは`requiresCompletion: true`とし、
`evidence[1]`にcompletion receiptを追加する。それ以外は`false`。`complete`では`evidence[0]`がcompletion receipt。
completion receiptは`contractHash / report / acceptance`を持ち、`acceptance`は全criterionと各`evidence`の組とする。
実テストのxUnitを含む現在の状態から生成したreportを使い、PASSという文字だけを書いたreportで代用しない。
G3で承認済みHY/RMのstatusを更新すると旧承認は失効するため、実検証reportはstatus更新前に保存する。
G3判断時は今回の承認だけを適用した状態でreportを再計算・照合する。他対象の失効やテスト失敗は免除されない。
requestとreceiptの必須field・順序は実engineの型と検査に合わせ、コマンド拒否を通常approveで回避しない。

### 契約内の判断

各追加作業を固定受入条件へ紐付け、なぜ達成に必要か記録する。SPの独立レビューには契約・仕様・形式的解釈と
その型/helperだけを渡し、実装担当と異なる担当が意味一致と範囲内であることを確認する。
範囲外改善は今回のblockerにしない。準備は受入検証を妨げる実際の問題の解消に限定する。

許可された判断は委任CLIで記録し、承認者には実エージェント名を使う。ユーザー名を代理で記入した通常の
`approve`や、noteに「委任」と書くだけの代用は禁止。契約hashと累積台帳へ結合し、拒否を手編集で回避しない。
hashが変わったら古い承認を使わず、独立レビューと範囲検査を経て委任の範囲内だけ再判断する。
機械的hash変更自体を理由に人間へ戻さず、実質的な範囲変更なら停止する。

### 予算と終端

準備・レビューは開始前に台帳へ記録し、FAIL・再試行も消費に含める。対象ID・契約名・担当を変えて
同じ作業の予算をリセットしない。使い切ったら追加案を捨て、残差と最小の再開案を報告する。
作業範囲内で手段を縮小しても、受入条件を削らない。reviewの新提案や形式化の追加を進捗に数えない。

完了には固定条件と実証拠の対応、実テストの成功、独立レビューが必要。ファイル数や内部モデルの完成だけで
利用者成果を達成したと称さない。全条件成立後は完了を記録して停止し、次RM・汎用化・追加レビューを開始しない。
G3は実リリースと実測値がある場合だけ扱い、実装・検証完了、release blocked、G3未達を区別する。
契約外の権限や操作時確認を要する不可逆操作は、委任で免除しない。

### 信頼境界

この仕組みは契約・判断の整合を検査するもので、Git書込権限を持つ者が人間であることの認証ではない。
自然言語の仕様が範囲内かは独立レビューで判断し、機械は対応・hash・予算・証拠の欠落を拒否する。
reviewer署名の暗号的本人確認、任意のOS操作の制限、証拠の現実世界での真正性を保証したとは扱わない。

## 通常の直接承認

承認は Lean 正本 (`Canon/Approvals.lean`) に埋め込み、**対象アーティファクトの内容の
正準直列化 + FNV-1a 64bit ハッシュに束縛**される。書込は `lake exe idchain approve` 経由のみで、
真正性は git 履歴が担保する。この skill は PB/VL/FA/HY/SP/LL/RM のどの対象にも共通で使う。

- **`approve` と `semantic-review` は別コマンド・別概念**: `lake exe idchain semantic-review`
  (SP の意味一致レビュー、Must-24) はこの skill の対象外。実施者は承認者ではなく
  実装コンテキストを持たない別エージェント、判定は pass/fail (合格/不合格) であって
  承認/却下ではない。semantic-review の実オペレーションは **idchain-spec** の手順に従う。
  この skill が扱うのはG1/G2/G3の**承認**そのものであり、SP を承認する前に
  semantic-review が pass 済みであることは `idchain-spec` 側の前提条件になる
  (`lake exe idchain check` の `semantic-review-missing` で機械検査される)。

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

通常モードではAskUserQuestion で提示する（委任モードは前節の契約検査を使う）:

- 対象 ID とその現内容 (仕様文・invariant・判断根拠の草稿など、呼び出し元 skill が用意したもの)
- 選択肢: 承認 / 却下 / 修正要求
- 承認者名は既知なら再質問しない。判断根拠は提示内容と実際の回答から記録し、不明な重要事項だけまとめて確認する

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
- 通常モードの失効した承認は**再びこの skill の手順 3a**で再承認する (`approve` コマンドは同一対象への
  再実行で自動的に古い承認を置換する)。失効した承認のまま次のフェーズ (TC 導出・実装) に
  進んではならない。
- 委任モードの再承認は「委任実行」の契約検査と専用CLIを使い、手順3aへfallbackしない。

## 呼び出し元との関係

- G2 (仕様承認): **idchain-spec** から呼ばれる。対象は `SP-<番号>`。SP の承認前に
  意味一致レビュー (semantic-review、idchain-spec の手順4) が pass 済みであることが前提。
- G1/G3 (Why/What 確定・成果レビュー): **idchain-discovery**/**idchain-retro** から呼ばれる。
  対象は PB/VL/FA/HY/LL。
- RM (ロードマップ項目、Must-29): **idchain-retro** (状態遷移・優先度変更時) や
  **idchain-discovery** (筋の良い仮説を一周に乗せる際の起票時) から呼ばれる。承認が要るのは
  `status` が `planned` → `inCycle` (次サイクルで着手確定) に遷移するときのみ — 承認なしで
  `inCycle` にすると `lake exe idchain check` が `in-cycle-roadmap-unapproved` 違反を出す。
  対象 ID は `RM-<番号>` (例 `RM-002`)、手順は 3a/3b と同じ (承認の場合は
  `lake exe idchain approve RM-002 --by <承認者> --note <判断根拠> --date <YYYY-MM-DD>`)。
  `planned` のままの追加・優先度変更や、`done`/`dropped` への遷移には承認は不要
  (ただし承認済み RM の内容をその後変更すると、他の対象と同様に `stale-approval` になる
  — 変更が意図的なら再度この skill の手順3a で再承認する)。
- 承認後の実装着手は **idchain-build** へ。
