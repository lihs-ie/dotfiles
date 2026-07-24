---
name: idchain-build
description: idchain の実装フェーズ (TC ID 注釈付き TDD → テスト実行 → TC⇄実テスト双方向突合 → 検証レポート → 独立 AI レビュー) を AI 自走で実行する。Use when (1) ユーザーが「実装して」「TDD で実装して」「検証レポートまで通して」と言ったとき、(2) /idchain-build [SP番号] を実行したとき、(3) 承認済み SP と導出済み TC がある状態で実装に着手するとき。前提として idchain-spec で G2 承認済み・TC 導出済みであること (check が green)。承認/却下は idchain-approve、仕様の追加・修正は idchain-spec に戻る。
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

### 3. テストコマンド実行 → 双方向突合

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
(「先に testCommand でテストを実行する」) — 手順 3 の実行順序を守ること。

### 4. 検証レポート生成

```bash
lake exe idchain report --date $(date +%Y-%m-%d)
```

- `reports/<日付>/verification-report.md` と `.json` が生成される。
- **総合判定が PASS (exit 0)** になるまで手順 1〜3 に戻って直す。
  FAIL の場合は「検証に紐づいていない仕様 N 件 / 仕様に紐づいていないテスト N 件」と
  仕様別 PASS/FAIL 表が原因の手がかりになる。

### 5. 独立 AI レビュー (Must-18、必須手順)

実装の意思決定過程・チャット履歴・試行錯誤を**一切共有しない別サブエージェント (fresh context)**
を起動し、以下だけを渡してレビューさせる:

- 変更差分 (`git diff`) とレビュー対象ファイル一覧
- レビュー観点: 品質 / セキュリティ / 設計 (実装の意図説明や「なぜこう書いたか」は渡さない)

CRITICAL/HIGH 指摘が出たら実装に反映し、手順 3〜4 を再実行して report を再度 green にする。
現時点の engine (`verification-report`) にはレビュー結果を格納する専用フィールドが無い
(構造化格納は M3 Must-18 で追加予定) ため、レビュー結果と対応内容は commit メッセージの
本文に残す。

### 6. views 再生成 + commit

```bash
lake exe idchain views
lake exe idchain views --check
```

```bash
git add <実装ファイル> <テストファイル> results/ idchain/reports/ idchain/views/
git commit -m "$(cat <<'EOF'
feat(<scope>): SP-047 を実装 (TC-047-1/2 green)

検証レポート: idchain/reports/<日付>/verification-report.md (総合判定 PASS)
独立レビュー: <指摘なし、または対応内容の要約>
EOF
)"
```

## 決定論的ゲートの実行順序 (このフェーズで必須)

```
lake build  →  lake exe idchain check  →  lake exe idchain crosscheck  →  lake exe idchain report --date <日付>
```

`crosscheck` は実テストコマンド実行後でないと `xunitPath` が読めず exit 2 になる。
`report` は `crosscheck` と同じ入力 (check の違反 + crosscheck の突合結果) を内包して
再計算するため、`crosscheck` が green になってから実行すること。

## 次のフェーズへ

- 検証レポートが PASS になり、独立レビューの指摘が解消したら実装フェーズは完了。
- 新しい仕様が必要になったら **idchain-spec** に戻る。
- 承認が失効した (SP 本文を後から直した等) 場合は **idchain-approve** で再承認する。
