# incident: read-only であるべき verifier が working tree を変異させ検証対象そのものを破壊した

- 日付: 2026-07-02 / 発見経路: proven-done dogfood (P1 verifier 並列実行) の runtime-verifier 外部観測 + static-verifier 本人申告
- 事象: P1 の verifier 並列実行中、read-only であるべき **static-verifier** が `kit-manifest.yml` の未コミット差分を `git checkout` で誤って破棄した。static-verifier は kit-manifest-update.sh による決定論再生成で自力復旧し実害は残らなかったが (本人が自白)、同時刻に **runtime-verifier** が「並行プロセスが manifest を flip-flop させた」と外部から観測していた。verifier は Bash を持つため、プロンプト上の「read-only」宣言は**約束に過ぎず**、tree 変異を止める機械的な検出層が存在しなかった。
- 影響: 検証対象のツリー**そのもの**が verifier によって書き換わった = **全 verdict の信頼性毀損**。どの verdict がどのツリー状態に対して下されたのかが不定になり、PASS/FAIL の意味が失われる。並列 verifier のうち 1 体でも tree を変異させると、他 verifier の判定基盤 (diff / working tree) が判定中にずれる (flip-flop 観測はこのレースの現れ)。
- 検出経路: P1 で導入した `tree_stamp` / `evidence-stamp.sh` が**事後**検出を可能にしていた (各 verdict がどのツリー状態のものかを決定論 stamp で記録)。今回は runtime-verifier の flip-flop 外部観測と static-verifier の自白の合致で顕在化した。ただしこれは事後検出であり、変異を**予防**する層ではない。
- 対処 (昇格済み・下記 2 点):
  1. verifier 4 種 (`dot_claude/agents/{static-verifier,runtime-verifier,spec-grader,done-evaluator}.md`) に **read-only 制約を明文化**: `git checkout`/`restore`/`stash`/`clean`/`reset` 等での working tree・index 変異を禁止、一時ファイルは repo 外 (`mktemp`) のみ、検証開始時と終了時に `evidence-stamp.sh` を実行し `self_stamp_before` / `self_stamp_after` を判定 JSON に記録 (両者不一致 = 自分が tree を汚した証跡)。
  2. `dot_claude/skills/proven-done/SKILL.md` に 1 文追加: orchestrator は各 verifier の起動前後で `evidence-stamp.sh` を実行して比較し、verifier による tree 変異を検出したら該当 verdict を無効化して差し戻す (self_stamp を verifier 自身に任せきりにせず、orchestrator 側でも外形的に挟む二重化)。
- 再発防止の残余リスク: read-only 遵守は依然として**プロンプト遵守に依存**する (verifier が Bash を持つ以上、tools 剥奪しない限り物理的には変異可能)。stamp 比較 (self_stamp + orchestrator の起動前後比較) は**変異の検出**を機械化するが、変異の**発生自体**は止められない。より強い封じ込め (verifier の Bash 剥奪 / read-only worktree でのサンドボックス実行) は将来の昇格候補として残す。
