import Idchain.Approve

/-!
# 対象 repo への導入 (U12)

engine を対象 repo の `idchain/engine/` に vendoring し (hermetic CI のため)、
Canon スケルトン・idchain.json・pre-commit hook・CI テンプレートを配置する。
既存ファイルは上書きしない (engine のみ `--update` で再同期)。
-/

namespace Idchain.Init

open Idchain

def canonLakefileTemplate : String :=
"name = \"idchain-canon\"
defaultTargets = [\"Canon\", \"idchain\"]

[[require]]
name = \"idchain\"
path = \"engine\"

[[lean_lib]]
name = \"Canon\"

[[lean_exe]]
name = \"idchain\"
root = \"IdchainMain\"
"

def idchainJsonTemplate : String :=
"{
  \"repoRoot\": \"..\",
  \"testFileRoots\": [],
  \"testFileExtensions\": [],
  \"xunitPath\": null,
  \"testCommand\": null,
  \"implementationPaths\": [],
  \"editAllowlist\": []
}
"

def canonRootTemplate : String :=
"import Canon.Artifacts
import Canon.Approvals
import Canon.SemanticReviews
import Canon.Gate
"

def artifactsTemplate : String :=
"import Idchain

/-!
# Canon: アーティファクト正本

ここが唯一の正本。人間向け文書は `lake exe idchain views` で生成する (生成物は編集禁止)。
ID は 1 始まり・単調増加・再利用禁止 (退役は retired へ移す)。
-/

namespace Canon

open Idchain

def problems : List Problem := []

def values : List Value := []

def featureAreas : List FeatureArea := []

def hypotheses : List Hypothesis := []

def specs : List Spec := []

def testCases : List TestCase := []

def learnings : List Learning := []

def roadmapItems : List RoadmapItem := []

def retired : List SimpleIdentifier := []

/-- プロジェクトの状態モデル。SP の不変条件はこの型の上で書く。 -/
structure Model where
  placeholder : Unit := ()

/-- 各 SP の形式的解釈 (SP 追加時にここへ invariant を足す)。 -/
def interpretations : List (SpecInterpretation Model) := []

end Canon
"

def gateTemplate : String :=
"import Canon.Artifacts
import Canon.Approvals
import Canon.SemanticReviews

/-!
# 無矛盾性ゲート

witness と証明が閉じない限りこのモジュール (と idchain exe) はビルドできない。
SP を追加したら interpretations と witness / 証明を更新すること。
仕様が増えて `decide` が重くなったら `native_decide` に切り替えてよい。
-/

namespace Canon

open Idchain

def registry : Registry := {
  problems := problems
  values := values
  featureAreas := featureAreas
  hypotheses := hypotheses
  specs := specs
  testCases := testCases
  learnings := learnings
  approvals := approvals
  retired := retired
  roadmapItems := roadmapItems
  semanticReviews := semanticReviews
}

/-- 無矛盾性 = 全 SP の不変条件を同時に満たす witness の存在。 -/
def gate : ConsistencyProof Model registry interpretations := {
  witness := {}
  sound := by intro interpretation mem; simp [interpretations] at mem
  complete := by decide
}

end Canon
"

def idchainMainTemplate : String :=
"import Canon
import Idchain.Cli

def main (args : List String) : IO UInt32 :=
  Idchain.Cli.run Canon.registry args
"

def preCommitTemplate : String :=
"#!/usr/bin/env bash
# idchain pre-commit: 決定論的ゲート (高速サブセット)
set -euo pipefail
cd \"$(git rev-parse --show-toplevel)/idchain\"
export PATH=\"$HOME/.elan/bin:$PATH\"
lake exe idchain check
lake exe idchain views --check
"

def ciWorkflowTemplate : String :=
"name: idchain
on:
  push:
  pull_request:

jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - name: Install elan
        run: |
          curl -sSf https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
          echo \"$HOME/.elan/bin\" >> \"$GITHUB_PATH\"
      - name: Build (無矛盾性証明ゲート込み)
        working-directory: idchain
        run: lake build
      - name: Traceability check
        working-directory: idchain
        run: lake exe idchain check
      - name: Views freshness
        working-directory: idchain
        run: lake exe idchain views --check
      - name: Approvals provenance warning
        run: |
          if git log -1 --format=%B | grep -q \"idchain-approve\"; then exit 0; fi
          if git diff HEAD~1 --name-only 2>/dev/null | grep -q \"idchain/Canon/Approvals.lean\"; then
            echo \"::warning::Approvals.lean が approve コマンド外で変更された可能性があります (commit message に idchain-approve がありません)\"
          fi
      # プロジェクト固有のテスト実行 + crosscheck / report は idchain.json の
      # testCommand を設定した上で以下を有効化する:
      # - name: Tests + crosscheck
      #   working-directory: idchain
      #   run: |
      #     (cd .. && <testCommand>)
      #     lake exe idchain crosscheck
"

partial def copyTree (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← source.readDir do
    let name := entry.fileName
    if name == ".lake" then
      pure ()
    else if (← entry.path.isDir) then
      copyTree entry.path (target / name)
    else
      IO.FS.writeBinFile (target / name) (← IO.FS.readBinFile entry.path)

def writeIfAbsent (path : System.FilePath) (content : String) : IO Unit := do
  if !(← path.pathExists) then
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile path content

def markExecutable (path : System.FilePath) : IO Unit := do
  let _ ← IO.Process.output { cmd := "chmod", args := #["+x", path.toString] }

def runInit (engineRoot : System.FilePath) (targetRepo : String) (update : Bool) : IO UInt32 := do
  let target : System.FilePath := targetRepo
  if !(← target.pathExists) then
    IO.eprintln s!"idchain init: 対象 {targetRepo} が存在しない"
    return 2
  let idchainDirectory := target / "idchain"
  if update then
    if !(← idchainDirectory.pathExists) then
      IO.eprintln "idchain init --update: 未初期化 (先に init を実行する)"
      return 2
    copyTree engineRoot (idchainDirectory / "engine")
    IO.println "idchain init --update: engine を再同期した"
    return 0
  if (← idchainDirectory.pathExists) then
    IO.eprintln "idchain init: 既に初期化済み (engine 更新は --update)"
    return 2
  copyTree engineRoot (idchainDirectory / "engine")
  writeIfAbsent (idchainDirectory / "lakefile.toml") canonLakefileTemplate
  IO.FS.writeFile (idchainDirectory / "lean-toolchain")
    (← IO.FS.readFile (engineRoot / "lean-toolchain"))
  writeIfAbsent (idchainDirectory / "idchain.json") idchainJsonTemplate
  writeIfAbsent (idchainDirectory / ".gitignore")
    ".lake/\nreports/\noracle-results.json\nbench-results.json\n.gate-status.json\n"
  writeIfAbsent (idchainDirectory / "Canon.lean") canonRootTemplate
  writeIfAbsent (idchainDirectory / "Canon" / "Artifacts.lean") artifactsTemplate
  writeIfAbsent (idchainDirectory / "Canon" / "Approvals.lean") (renderApprovalsLean [])
  writeIfAbsent (idchainDirectory / "Canon" / "SemanticReviews.lean") (renderSemanticReviewsLean [])
  writeIfAbsent (idchainDirectory / "Canon" / "Gate.lean") gateTemplate
  writeIfAbsent (idchainDirectory / "IdchainMain.lean") idchainMainTemplate
  writeIfAbsent (idchainDirectory / "hooks" / "pre-commit") preCommitTemplate
  markExecutable (idchainDirectory / "hooks" / "pre-commit")
  writeIfAbsent (target / ".github" / "workflows" / "idchain.yml") ciWorkflowTemplate
  let gitHooks := target / ".git" / "hooks"
  if (← gitHooks.pathExists) then
    if (← (gitHooks / "pre-commit").pathExists) then
      IO.println "既存の .git/hooks/pre-commit を検出したため上書きしない。idchain/hooks/pre-commit の内容を既存 hook に手動で追記すること"
    else
      IO.FS.writeFile (gitHooks / "pre-commit") preCommitTemplate
      markExecutable (gitHooks / "pre-commit")
      IO.println "pre-commit hook を .git/hooks に導入した"
  IO.println s!"idchain init: {targetRepo}/idchain を初期化した"
  IO.println "次の一歩: cd idchain && lake build && lake exe idchain check"
  return 0

/-- engine root の自動検出: cwd が engine 自体か、canon package (engine/ を持つ) か。 -/
def detectEngineRoot : IO (Option System.FilePath) := do
  let currentDirectory ← IO.currentDir
  if (← (currentDirectory / "Idchain.lean").pathExists) then
    return some currentDirectory
  if (← (currentDirectory / "engine" / "Idchain.lean").pathExists) then
    return some (currentDirectory / "engine")
  return none

end Idchain.Init
