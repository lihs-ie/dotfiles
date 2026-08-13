---
name: idchain-init
description: 対象 repo に idchain (Lean 4 正本による ID トレーサビリティ開発ハーネス) を導入する。engine の vendoring・Canon スケルトン生成・idchain.json アダプタ設定・pre-commit hook 確認・初回 commit までを行う。Use when (1) ユーザーが「idchain 入れて」「idchain 初期化して」「ID トレーサビリティ導入して」と言ったとき、(2) $idchain-init [対象repoの絶対パス] を実行したとき、(3) 既に導入済みの repo で engine だけ最新化したいとき (--update)。仕様フェーズは idchain-spec、実装フェーズは idchain-build、個別の承認操作は idchain-approve を使う (この skill は導入専用で、それらの前提を作るだけ)。
---

# idchain-init

idchain は「正本 = 対象 repo の `idchain/Canon/*.lean` (Lean 4)」とする ID トレーサビリティ
ハーネス。仕様書・テスト設計書・Why/What・学び台帳は `lake exe idchain views` による生成物で
編集禁止。詳細仕様は `docs/specs/idchain.md` を参照。この skill はその **導入 (init) 専用**。

## 前提

```bash
export PATH="$HOME/.elan/bin:$PATH"
which lake  # 見つからなければ elan/lean のセットアップを先に行う
```

- engine は共通正本の digest 検証後、chezmoi により `~/.codex/idchain/engine/` へ実体同期される。
- init 実行に使う exe は **engine 側の `idchain-dev`**(対象 repo 側の `idchain` exe とは別物。
  対象 repo にはまだ何もないので、engine 単体の exe で「対象 repo に何を書き込むか」を実行する)。

## 手順 (新規導入)

### 1. 未導入であることを確認

```bash
ls <対象repoの絶対パス>/idchain 2>&1  # 存在すれば「既に初期化済み」なので --update 手順へ
```

### 2. engine から init を実行

```bash
cd ~/.codex/idchain/engine
export PATH="$HOME/.elan/bin:$PATH"
lake exe idchain-dev init <対象repoの絶対パス>
```

- 対象パスは **絶対パス**で渡す (`cd` 済みの cwd は engine 側なので相対パスは事故る)。
- 生成される (既存ファイルは上書きしない):
  - `<対象repo>/idchain/engine/` — engine の vendoring コピー (`.lake/` は除外)
  - `<対象repo>/idchain/lakefile.toml` / `lean-toolchain` / `.gitignore`
  - `<対象repo>/idchain/Canon.lean` (root import) / `Canon/Artifacts.lean` (空スケルトン) /
    `Canon/Approvals.lean` (空 `[]`) / `Canon/Gate.lean` (witness `{}` の空無矛盾性ゲート) /
    `Canon/SemanticReviews.lean` (空 `[]`、`lake exe idchain semantic-review` 専用の書込先、Must-24)
  - `<対象repo>/idchain/views/roadmap.md` は初回時点では未生成 (RM が 0 件のため
    `lake exe idchain views` 実行後に生成される。他の views と同様に DO NOT EDIT)
  - `<対象repo>/idchain/IdchainMain.lean` (`Idchain.Cli.run Canon.registry args` を呼ぶだけ)
  - `<対象repo>/idchain/idchain.json` (アダプタ設定。値は全て空/null — 手順 3 で埋める)
  - `<対象repo>/idchain/hooks/pre-commit` (実行権限付与済み)
  - `<対象repo>/.github/workflows/idchain.yml` (CI テンプレート)
  - `<対象repo>/.git/hooks/pre-commit` (`.git/hooks` が存在する場合のみ自動配置)
- 既に `idchain/` が存在する場合は exit 2 (`idchain init: 既に初期化済み`)。手順を止めて後述の
  `--update` 手順に切り替える。

### 3. idchain.json のアダプタ設定を対象プロジェクトの実態に合わせる

init 直後の `idchain.json` は空テンプレートなので、対象プロジェクトのテスト実行系に
合わせて埋める。フィールドの意味 (`Idchain.Config`):

| フィールド | 意味 |
|---|---|
| `repoRoot` | `idchain/` から見た対象 repo ルートの相対パス (既定 `..`、通常変更不要) |
| `testFileRoots` | テストファイルを探索するディレクトリ (repoRoot 相対、複数可) |
| `testFileExtensions` | 対象拡張子 (例 `.swift`) |
| `xunitPath` | テスト実行結果の xunit XML パス (crosscheck/report が読む。未設定なら null で graceful skip) |
| `testCommand` | テスト実行コマンド (xunit を `xunitPath` に出力するもの。lake exe からは自動実行されない — `idchain-build` で手動/CI 実行する) |
| `implementationPaths` | 実装コードの所在 (M4 の編集ブロック hook 用。現時点では参照専用) |
| `editAllowlist` | 編集ブロック hook の例外パス (同上) |

Swift プロジェクトの例 (fixture `tests/fixtures/idchain-sample/idchain/idchain.json` と同形):

```json
{
  "repoRoot": "..",
  "testFileRoots": ["Tests"],
  "testFileExtensions": [".swift"],
  "xunitPath": "results/latest-tests.xml",
  "testCommand": "swift test --xunit-output results/latest-tests.xml",
  "implementationPaths": ["Sources/"],
  "editAllowlist": []
}
```

- `testCommand` は必ず `--xunit-output <xunitPath と同じパス>` を含めること (crosscheck/report が
  読むファイルと不一致だと `missing` エラーで exit 2 になる)。
- `xunitPath`/`testCommand` は Swift 以外にも拡張可能 (adapter 設定のみで差し替え、Lean 側の
  パーサ実装追加は不要な範囲では)。未対応形式の場合は事前にエスカレーションする。

### 4. 初回ビルド (型検査 + 無矛盾性証明ゲート)

```bash
cd <対象repo>/idchain
export PATH="$HOME/.elan/bin:$PATH"
lake build
```

- 空スケルトンの witness は `{}` (空 Model)、`interpretations := []` なので証明は自明に閉じる。
  ここで失敗する場合は engine vendoring 自体が壊れているので `--update` を疑う。

### 5. pre-commit hook の確認

```bash
ls -l <対象repo>/.git/hooks/pre-commit
cat <対象repo>/idchain/hooks/pre-commit
```

- 中身は `cd idchain && lake exe idchain check && lake exe idchain views --check` の高速サブセット。
- `.git/hooks` が repo 作成直後で存在しなかった場合は自動配置されていないので、
  `<対象repo>/idchain/hooks/pre-commit` の内容を `.git/hooks/pre-commit` にコピーし
  `chmod +x` する。

### 6. 初回 commit

```bash
cd <対象repo>
git add idchain/ .github/workflows/idchain.yml
git commit -m "$(cat <<'EOF'
chore(idchain): idchain ハーネスを導入

engine vendoring + Canon スケルトン + idchain.json アダプタ設定 (<プロジェクト名>)。
EOF
)"
```

- scope はプロジェクト規約 (`git-workflow.md`) に従いサービス名/モジュール名を使う。
- ここまでで PB/VL/FA/HY/SP はまだ 0 件。次は **idchain-spec** で SP を起票する。

## 手順 (既導入 repo の engine 更新: `--update`)

```bash
cd ~/.codex/idchain/engine
export PATH="$HOME/.elan/bin:$PATH"
lake exe idchain-dev init <対象repoの絶対パス> --update
```

- `<対象repo>/idchain/` が存在しない場合は exit 2 (`未初期化 (先に init を実行する)`)。
- `--update` は `<対象repo>/idchain/engine/` のみを再同期する。`Canon/*.lean` / `idchain.json` /
  hook / CI テンプレートには一切触れない (Canon は正本、手で書いたものを守る)。
- 更新後は必ず再ビルドして退行がないか確認する:

```bash
cd <対象repo>/idchain
lake build
lake exe idchain check
```

- commit する場合は `chore(idchain): engine を最新化` のような scope で。

## 次のフェーズへ

- SP の起草・G2 承認・TC 導出 → **idchain-spec**
- TDD 実装・crosscheck・独立レビュー → **idchain-build**
- 個別 ID の承認/却下操作 (G1/G2/G3 共通) → **idchain-approve**
