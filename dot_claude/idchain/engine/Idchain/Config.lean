import Lean.Data.Json

/-!
# プロジェクトアダプタ設定 (`idchain/idchain.json`)

対象 repo 固有の結線点 (テストファイルの所在・xunit 出力・テストコマンド等)。
パスは repo root 相対で書き、exe は `repoRoot` (既定 `..` = idchain/ の親) に対して解決する。
-/

namespace Idchain

structure Config where
  repoRoot : String := ".."
  testFileRoots : List String := []
  testFileExtensions : List String := []
  xunitPath : Option String := none
  testCommand : Option String := none
  implementationPaths : List String := []
  editAllowlist : List String := []
  deriving Repr, DecidableEq, Inhabited

private def getStringList (json : Lean.Json) (key : String) : Except String (List String) :=
  match json.getObjVal? key with
  | .error _ => .ok []
  | .ok .null => .ok []
  | .ok value => do
    let entries ← value.getArr?
    entries.toList.mapM (·.getStr?)

private def getOptionalString (json : Lean.Json) (key : String) : Except String (Option String) :=
  match json.getObjVal? key with
  | .error _ => .ok none
  | .ok .null => .ok none
  | .ok value => do pure (some (← value.getStr?))

def Config.parse (raw : String) : Except String Config := do
  let json ← Lean.Json.parse raw
  let repoRoot ← match json.getObjVal? "repoRoot" with
    | .error _ => pure ".."
    | .ok value => value.getStr?
  pure {
    repoRoot
    testFileRoots := ← getStringList json "testFileRoots"
    testFileExtensions := ← getStringList json "testFileExtensions"
    xunitPath := ← getOptionalString json "xunitPath"
    testCommand := ← getOptionalString json "testCommand"
    implementationPaths := ← getStringList json "implementationPaths"
    editAllowlist := ← getStringList json "editAllowlist"
  }

end Idchain
