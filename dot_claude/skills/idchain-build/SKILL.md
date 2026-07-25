---
name: idchain-build
description: idchain の実装フェーズ (TC ID 注釈付き TDD → 再現テスト規約 → テスト実行 → TC⇄実テスト双方向突合 → ベンチ専門家評価 → 検証レポート → 独立 AI レビュー) を AI 自走で実行する。Use when (1) ユーザーが「実装して」「TDD で実装して」「検証レポートまで通して」と言ったとき、(2) /idchain-build [SP番号] を実行したとき、(3) 承認済み SP と導出済み TC がある状態で実装に着手するとき、(4) 実装中・検証中にバグを発見して再現テストから直したいとき。前提として idchain-spec で G2 承認済み・TC 導出済みであること (check が green)。承認/却下は idchain-approve、仕様の追加・修正は idchain-spec に戻る。
---

# idchain-build

実装コードは ID の鎖の**外**にある (発表 p.36)。正しさは「TC 由来テストが実行され、
かつ正本の TC と 1 対 1 で突合すること」で保証する。実装フェーズは人間ゲートが無い
AI 自走区間だが、**独立コンテキストのレビュー**を必須手順とする (発表 p.40
「同じコンテキストは同じ見落としを生む」)。

## 前提確認

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake exe idchain check
```

- exit 0 であること。対象 SP が承認済みで TC が導出済み (`idchain-spec` 完了済み) を意味する。
- exit 1 なら **idchain-spec に戻る** (未承認 SP・孤児 TC の状態で実装を始めない)。

## 手順

### 1. TDD: TC ID 注釈付きテストを先に書く (RED)

正本の TC 一覧 (`Canon/Artifacts.lean` の `testCases`) を確認し、各 TC ごとに
実装言語側のテストを **TC ID を区切り文字 (英数字とハイフン以外) で囲んだ表示名/テスト名**
で書く。区切りが無いと突合エンジンが ID を切り出せない。

```swift
import Testing

@Test("TC-047-1: 明細3件で小計一致")
func subtotalMatchesThreeItems() { /* まだ実装が無いので失敗する (RED) */ }

@Test("TC-047-2: 明細0件で小計0")
func subtotalZeroItems() { }
```

- TC ID 表記は正本と**厳密に一致**させる (SP 番号側はゼロ埋め3桁 `047`、枝番側はゼロ埋め
  なし `1`)。`TC-47-1` や `TC-047-01` は突合エンジンが別物として扱う (未知参照/未実装扱いになる)。
- まずテストを走らせて失敗を確認する (RED)。

### 2. 実装 (GREEN) → リファクタ

仕様 (SP の text と invariant) だけを根拠に最小実装を書き、テストを通す。
通った後にリファクタリングし、都度テストが green のままであることを確認する。

### 3. バグ発見時: 再現テストが先 (Must-30、実装中・検証中いずれで見つけても適用)

実装中・検証中 (この後の手順4〜7 のどこでも) にバグを発見した場合、**修正を先に書いてはいけない**。
必ず以下の順序を守る:

1. **先に再現 TC を canon に導出する**: `kind = .regression`、ID は導出元 SP の**既存枝番に
   続けて追加** (例: SP-047 に TC-047-1/2 が既にあれば `TC-047-3`)。バグの現象を導出元とする
   SP が正本に存在しない場合は、この手順を中断して**idchain-spec に戻り SP 起草から**やり直す
   (意味一致レビュー・G2 承認を含む正規のフローを飛ばして再現 TC だけ後付けしない)。
   ```lean
   def testCases : List TestCase := [
     ⟨⟨47, 1⟩, "明細3件 → 小計 = 合計", .example⟩,
     ⟨⟨47, 2⟩, "明細0件 → 小計 = 0", .example⟩,
     ⟨⟨47, 3⟩, "回帰: <発見したバグの再現内容>", .regression⟩
   ]
   ```
2. **テストで RED 再現を確認する**: 手順1の TC に対応するテストを実装言語側に書き、
   バグが再現して失敗することを確認する。
3. **修正する**。
4. **GREEN を確認する**。

修正を先にしてから帳尻合わせで再現テストを書く (=「修正先行」) ことは禁止。RED を確認
できていないテストは、そのバグを実際に再現できている保証がない。

```bash
lake build
lake exe idchain check   # orphan-spec / test-case-for-unapproved-spec が0件であることを確認
```

### 4. テストコマンド実行 → 双方向突合

`idchain.json` の `testCommand` を対象 repo ルートから実行し、`xunitPath` に結果を出力する
(lake exe はテストを自動実行しない。ここは自分で/CI で実行する):

```bash
cd <対象repo>
swift test --xunit-output results/latest-tests.xml   # idchain.json の testCommand をそのまま使う
```

```bash
cd <対象repo>/idchain
lake exe idchain crosscheck
```

以下が**全件ゼロ**になるまで直さない:

| 区分 | 意味 | 直し方 |
|---|---|---|
| 孤児テスト (orphan test) | 実行されたテストの名前に TC ID が無い | テスト名に TC ID 注釈を追加 |
| 未知の TC 参照 (unknown) | コード/実行結果に現れた TC ID が正本に無い | 正本の typo か削除された TC の残骸。TC を正本に足すか注釈を消す |
| 未実装 TC (unimplemented) | 正本の TC がテストコードのどこにも無い | そのテストをまだ書いていない。手順 1 に戻る |
| 未実行 TC (unexecuted) | コードにはあるが xunit 結果に無い | テストコマンドの実行対象漏れ・スキップ設定を確認 |

`xunitPath` が `idchain.json` で未設定の場合は構造検査 (未知参照・未実装) のみ判定され
graceful に進む。`xunitPath` を設定しているのに結果ファイルが無い場合は exit 2
(「先に testCommand でテストを実行する」) — 手順 4 の実行順序を守ること。

### 5. ベンチ実行 → 専門家評価 (Must-21/27)

`Canon/Artifacts.lean` の `benchmarks` が 1 件も無いプロジェクトではこの手順全体を
スキップしてよい (graceful skip、手順6 の report にも「未実施」と記録されるだけで
FAIL にはならない)。設定がある場合のみ以下を行う。

```bash
lake exe idchain bench
```

- 各ベンチマークの計測値と赤黄緑判定 (`bench-results.json` に保存) が出力される。
  **この赤黄緑の機械判定は変更不能な事実** — 次のレビューでエージェントが覆してはならない。

実装の意思決定過程を共有しない別サブエージェント (fresh context) を起動し、
`bench-results.json` と過去の `reports/*/verification-report.json` (傾向比較用) を渡して
評価させる。**このエージェントの役割は判定の解釈・改善提案に限られ、赤黄緑の判定そのものを
書き換えることはできない** (楽観バイアスの構造的禁止)。評価結果は
`reports/<日付>/bench-expert-review.md` に保存する。

```bash
mkdir -p idchain/reports/$(date +%Y-%m-%d)
# 評価結果を idchain/reports/<日付>/bench-expert-review.md に保存する
```

- **赤/黄判定が出た場合**、`source = "bench:<ベンチマーク名>"` の RM を `Canon/Artifacts.lean`
  の `roadmapItems` に起票しないと、手順6 の `lake exe idchain report` が **総合判定 FAIL**
  になる (Must-28「反映の省略は禁止」の機械化、`unreflectedBenchmarks` による検出)。
  RM の起票手順は idchain-retro の「ロードマップを書き換える」に従う。
  green のベンチマークには RM は不要。

### 6. 検証レポート生成

```bash
lake exe idchain report --date $(date +%Y-%m-%d)
```

- `reports/<日付>/verification-report.md` と `.json` が生成される。手順5 で `bench-results.json`
  を生成済みなら「## ベンチマーク」節に自動的に取り込まれる。
- **総合判定が PASS (exit 0)** になるまで手順 1〜5 に戻って直す。
  FAIL の場合は「検証に紐づいていない仕様 N 件 / 仕様に紐づいていないテスト N 件」と
  仕様別 PASS/FAIL 表、および「## ベンチマーク」節の「⚠ 未反映」表示が原因の手がかりになる。

### 7. 独立 AI レビュー (Must-18、必須手順)

実装の意思決定過程・チャット履歴・試行錯誤を**一切共有しない別サブエージェント (fresh context)**
を起動し、以下だけを渡してレビューさせる:

- 変更差分 (`git diff`) とレビュー対象ファイル一覧
- レビュー観点: 品質 / セキュリティ / 設計 (実装の意図説明や「なぜこう書いたか」は渡さない)

CRITICAL/HIGH 指摘が出たら実装に反映し、手順 4〜6 を再実行して report を再度 green にする。
現時点の engine (`verification-report`) にはレビュー結果を格納する専用フィールドが無い
(構造化格納は M3 Must-18 で追加予定) ため、レビュー結果と対応内容は commit メッセージの
本文に残す。

### 8. views 再生成 + commit

```bash
lake exe idchain views
lake exe idchain views --check
```

```bash
git add <実装ファイル> <テストファイル> results/ idchain/Canon/Artifacts.lean \
  idchain/bench-results.json idchain/reports/ idchain/views/
git commit -m "$(cat <<'EOF'
feat(<scope>): SP-047 を実装 (TC-047-1/2 green)

検証レポート: idchain/reports/<日付>/verification-report.md (総合判定 PASS)
独立レビュー: <指摘なし、または対応内容の要約>
ベンチ専門家評価: idchain/reports/<日付>/bench-expert-review.md (<未実施 または要約>)
EOF
)"
```

## 決定論的ゲートの実行順序 (このフェーズで必須)

```
lake build  →  lake exe idchain check  →  lake exe idchain crosscheck
  →  lake exe idchain bench (設定時のみ)  →  lake exe idchain report --date <日付>
```

`crosscheck` は実テストコマンド実行後でないと `xunitPath` が読めず exit 2 になる。
`bench` は `benchmarks` が未設定なら graceful skip でよい。`report` は `crosscheck` と同じ入力
(check の違反 + crosscheck の突合結果) に加え、cwd の `bench-results.json` があれば取り込んで
再計算するため、**bench を実施する場合は report より先に実行すること** (report 生成後に
bench を実行しても、その結果は report に反映されない)。

## 次のフェーズへ

- 検証レポートが PASS になり、独立レビューの指摘が解消したら実装フェーズは完了。
- 新しい仕様が必要になったら **idchain-spec** に戻る。
- 承認が失効した (SP 本文を後から直した等) 場合は **idchain-approve** で再承認する。
