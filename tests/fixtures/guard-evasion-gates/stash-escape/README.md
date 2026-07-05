# stash-escape fixtures (Must-4)

`git stash` state cannot be committed as static fixture files (stashes are per-repository refs, not
tracked file content), so these fixtures are built dynamically at test-runtime as scratch git repos
under `mktemp -d` rather than as static files under this directory.

See `tests/run-shell-tests.sh`:
- `setup_stash_escape_base_repo()` — builds the scratch repo (tracked `task-file.txt` /
  `unrelated-file.txt`, `.agent-evidence/wiring-map.json` listing `task-file.txt` as a task-touched
  file).
- `verify-guard-integrity stash-baseline (Must-3) ...` — Step-0-simulation baseline recording
  diff/string-equality fixture.
- `verify-guard-integrity stash-escape (a) baseline後に新規stash無し -> exit 0`
- `verify-guard-integrity stash-escape (b) 無関係な新規stash ... -> exit 0`
- `verify-guard-integrity stash-escape (c) タスク対象ファイルをタッチする新規stash -> POLICY VIOLATION ...`

This file exists only to give the fixture category a discoverable path
(`docs/specs/guard-evasion-gates.md` Must-4 Done-When); no static content belongs here.
