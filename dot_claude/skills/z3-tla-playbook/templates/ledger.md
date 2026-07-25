# 検証台帳 — <対象領域>

最終成果物は「証明の山」ではなく、**実装の主張 / 機械検査の結果 / ドメインへの確認質問** の台帳。
形式手法はバグ検出だけでなく、仕様と認識を揃えるための共通言語として使う。

- 対象コミット: `<sha>`
- 検証ディレクトリ: `.formal/`
- 再実行: `bash ~/.claude/skills/z3-tla-playbook/scripts/run-checks.sh --dir .formal`

---

## A. 実装の主張 (吸い出した仕様)

「宣言された仕様」と「暗黙の挙動」を分けて記録する。**出典 (file:line) を必ず付ける**。

| # | 主張 | 種別 | 出典 | モデル化 |
|---|---|---|---|---|
| A-1 | 上限に達したら配信しない | 宣言 (コメント/テスト名) | `src/serve.ts:42` | `NeverOverCap` |
| A-2 | 設定が空のときは全許可 | 暗黙 (default 値) | `src/config.ts:18` | 未 |

---

## B. 機械検査の結果

`HOLDS` は契約 (regression guard) としてロックされ、将来どちらかが変わったら赤くなる。

| # | 性質 | ツール | 結果 | 根拠 |
|---|---|---|---|---|
| B-1 | `NeverOverCap` | TLA+ | HOLDS | `.formal/specs/Example.tla` |
| B-2 | `NeverServeMinor` | Z3 | HOLDS | `.formal/models/example_cap.py` |
| B-3 | `ServesEveryAdult` | Z3 | REFUTED | 反例: `age=70` |

### broken-variant の証明 (検査が load-bearing であること)

| 変種 | 外した保護 | 期待 | 実際 |
|---|---|---|---|
| `Example__StaleRead` | 判定と書き込みの原子性 | VIOLATE | VIOLATE |
| `example_cap__guard-removed` | 下限年齢ガード | 赤 | 赤 |

---

## C. ドメインへの確認質問 (反例 → 会話)

反例は「バグ報告」であると同時に**認識合わせの起点**。意図なら仕様として明文化、意図でないならバグ。

| # | 反例 (witness) | 質問 | 回答 | 落とし所 |
|---|---|---|---|---|
| C-1 | `age=70` で配信されない | 65 歳超の除外は意図か? | 未 | 仕様明文化 / バグ |

---

## D. 残リスク・未検証

- モデル↔コードのギャップ: `<どこを手で抽象したか>`
- trace-checking の有無: `<実ログと突き合わせたか>`
- 意図的に検証しなかった領域と理由 (§ やめ時): `<確率的性質など>`
