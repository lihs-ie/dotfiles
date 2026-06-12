<!-- GENERATED (dogfood) by agent-policy-kit from dot_claude/docs/agent-policy.md. 直接編集せず正本を直して再適用すること。 -->
# CLAUDE.md — dotfiles

chezmoi 管理の個人 dotfiles repo。Claude Code 向けの規約は下記 (詳細・結線点・rubric は `AGENTS.md`)。

## Agent Policy

モック濫用と未配線完了報告を防ぐ規約の Claude Code 向け要点。詳細・結線点・rubric は `AGENTS.md` を参照。

### Working style
- 結論から述べる。進捗報告は各主張を**このセッションの tool result で監査**し、未検証は未検証と明示する。
- turn を終えるのは task complete か genuinely blocked のときだけ。「次に…する」で終えない。
- 仕様に必要な最小実装に留め、不要な refactor / 将来用抽象化を足さない。

### Repository rules (二大事故防止)
- 本番コードに **mock/stub/fake/dummy/spy** を入れない (テストパス以外)。
- 本番経路に **test-only bypass** (`NODE_ENV === 'test'` 等) を入れない。
- **placeholder stub** (`err501` / `notImplemented` / `todo!()` 等) を本番に残さない。wire-first で結線を先に通す。
- 例外は `ci/allowlist.yml` に owner/reason/expires_at 付きで登録 (無期限禁止)。

### Done (二段門)
- 要求挙動が **real public entrypoint から到達可能**で、**観測可能挙動を実行 assert** した。
- 構造配線 + データフロー配線が揃う。build / lint / typecheck / unit / contract が通る。
- ① 証跡が揃う (`commands.txt` / `wiring-map.json` / `completion-report.md`)
  ② done-evaluator が spec の Must を fresh context で `done` 判定。

### Required evidence before claiming done
- 実行コマンドと exit code / 到達した entrypoint / wiring map / spec 参照 / 残リスク。

### Escalate instead of guessing when
- migration / data backfill が要る、API 契約を変える、新依存が要る、root cause の証拠が曖昧。
