# タイトル
ADR-001: idchain の論理正本を共有し Claude Code と Codex へホスト別配布する

# ステータス
承認済み

# コンテキスト
idchain は、添付資料「『動くだけ』のその先へ」で示された、課題探索から仕様、形式検査、人間承認、テスト導出、実装、検証、学習までを ID の鎖で管理する開発手法を実行する仕組みである。

既存実装は `dot_claude` を中心に構成され、Claude Code の Skill、hook、Lean エンジンを提供していた。Codex でも全工程を実行可能にし、chezmoi の `dot_codex` から `~/.codex` へ配布する必要がある。

次の代替案を検討した。

- Lean エンジンと全 Skill を `dot_codex` に複製する案は不採用とする。41 ファイル以上の重複により二重正本とドリフトが生じ、30 ファイルを超える変更を block とするリポジトリ規約にも抵触する。
- Codex から `~/.claude` のエンジンを直接参照する案は不採用とする。Codex 単独で利用できず、`dot_codex` で管理する要件を満たさない。
- `dot_claude` を論理正本として維持し、Codex 固有成果物を決定論的に生成・配布する案を採用する。

# 決定
idchain の共通 Skill と Lean エンジンは `dot_claude` を論理正本とする。

Codex 用の統合ルーター `idchain` と6個のフェーズ Skill は、`scripts/sync-idchain-codex.sh` により `dot_codex/skills` へ決定論的に生成する。生成物の手編集は禁止し、`--check` により正本とのドリフトを検出する。

Lean エンジンはリポジトリ内で複製しない。正本のツリーダイジェストを `dot_codex/idchain/engine-source.sha256` に記録し、chezmoi の `run_onchange` スクリプトがダイジェストを検証して `~/.codex/idchain/engine` へ配置する。

Codex の `PreToolUse` hook は `apply_patch` を対象にし、未承認 SP のみが存在する状態で実装ファイルへの編集を拒否する。`idchain` 正本、テストルート、明示 allowlist は編集可能とする。shell コマンドによる書き込みはこの hook の保護範囲外とし、決定論的ゲート、pre-commit、CI で検出する。

`~/.codex` への反映は明示した対象パスだけに限定する。Codex が hook 設定を信頼していることは `/hooks` で確認する。

# 影響
Positive:

- Claude Code と Codex が同じ Lean 正本と開発ライフサイクルを利用できる。
- Codex では `$idchain` から状態に応じた全工程を再開できる。
- Skill のドリフトとエンジンの改変を決定論的に検出できる。
- G1、G2、G3 の人間判断を維持し、承認前の実装着手を抑止できる。
- リポジトリ内で Lean エンジンを重複管理せずに済む。

Negative:

- `dot_claude` というホスト名を含むディレクトリが共通論理正本として残る。
- Codex Skill を変更する場合は生成スクリプトを経由する必要がある。
- エンジン配布は chezmoi の `run_onchange` と SHA-256 ダイジェスト更新に依存する。
- `apply_patch` 以外の書き込みは Codex hook 単独では阻止できない。
- hook の利用開始時に Codex 上で設定を信頼する手動操作が必要になる。

# コンプライアンス
次の自動検査を必須とする。

- `bash scripts/sync-idchain-codex.sh --check`
- `bash tests/idchain-codex-hook-tests.sh`
- `bash tests/idchain-codex-sync-tests.sh`
- Codex 用7 Skillに対する `quick_validate.py`
- `lake build`
- `lake exe tests`
- `bash scripts/verify-wiring.sh`
- リポジトリ既定の test-double、test-bypass、placeholder、allowlist、failure-class、quarantine 検査

`wiring_manifest.yml` は共通 Skill、エンジンダイジェスト、Codex hook、chezmoi エンジン同期の結線を検査する。

配布後は `~/.codex` の各ファイルと `dot_codex` の一致、エンジンダイジェスト、実行権限、既存 `config.toml` が変更されていないことを確認する。Codex 上では `/hooks` を開き、idchain hook が信頼済みであることを手動確認する。

# 備考
- 著者: Codex
- 承認日: 2026-08-13
- 承認者: ユーザー
- 最終更新日: 2026-08-13
- 変更点: 初版。Claude Code と Codex 間の idchain 共通正本、生成、配布、編集ゲートを決定した。
