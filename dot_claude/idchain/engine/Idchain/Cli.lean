import Idchain.Checks
import Idchain.Config
import Idchain.Export
import Idchain.Crosscheck

/-!
# CLI (対象 repo の IdchainMain が呼ぶライブラリ層)

対象 repo では init が生成する `IdchainMain.lean` が Canon の Registry を注入して
`Idchain.Cli.run` を呼ぶ。実行ディレクトリ規約: `idchain/` (lake package root) から起動し、
`idchain.json` の `repoRoot` (既定 `..`) で repo 相対パスを解決する。
engine 単体の `Main.lean` は空 Registry での smoke 用。
-/

namespace Idchain.Cli

open Idchain

def renderViolation (violation : Violation) : String :=
  s!"VIOLATION [{violation.kind.label}] {violation.identifier}: {violation.message}"

def runCheck (registry : Registry) : IO UInt32 := do
  let violations := registry.checkAll
  if violations.isEmpty then
    IO.println "idchain check: 違反 0 件 (ID の鎖は閉じている)"
    return 0
  else
    for violation in violations do
      IO.println (renderViolation violation)
    IO.println s!"idchain check: 違反 {violations.length} 件"
    return 1

def runExport (registry : Registry) : IO UInt32 := do
  IO.println (exportJson registry)
  return 0

def loadConfig : IO (Except String Config) := do
  let path : System.FilePath := "idchain.json"
  if (← path.pathExists) then
    pure (Config.parse (← IO.FS.readFile path))
  else
    pure (.ok {})

partial def collectFiles (root : System.FilePath) (extensions : List String) :
    IO (List System.FilePath) := do
  if !(← root.pathExists) then
    return []
  if (← root.isDir) then
    let entries ← root.readDir
    let mut results := []
    for entry in entries do
      results := results ++ (← collectFiles entry.path extensions)
    return results
  else if extensions.isEmpty || extensions.any (root.toString.endsWith ·) then
    return [root]
  else
    return []

def readTestFiles (config : Config) : IO (List (String × String)) := do
  let repoRoot : System.FilePath := config.repoRoot
  let mut fileContents := []
  for rootRelative in config.testFileRoots do
    let files ← collectFiles (repoRoot / rootRelative) config.testFileExtensions
    for file in files do
      fileContents := fileContents ++ [(file.toString, ← IO.FS.readFile file)]
  return fileContents

inductive XunitAvailability where
  | loaded (cases : List XunitCase)
  | unconfigured
  | missing (path : System.FilePath)

def loadXunit (config : Config) : IO XunitAvailability := do
  match config.xunitPath with
  | none => return .unconfigured
  | some relative =>
    let path := (config.repoRoot : System.FilePath) / relative
    if (← path.pathExists) then
      return .loaded (parseXunit (← IO.FS.readFile path))
    else
      return .missing path

def renderCrosscheck (result : CrosscheckResult) (executionKnown : Bool) : List String :=
  let section' (title : String) (items : List String) : List String :=
    if items.isEmpty then [] else s!"{title} ({items.length} 件):" :: items.map ("  - " ++ ·)
  section' "仕様に紐づいていないテスト (orphan test)" result.orphanTests
  ++ section' "未知の TC 参照 (正本に存在しない)" (result.unknownReferences.map (·.render))
  ++ section' "未実装 TC (テストコードに不在)" (result.unimplementedTestCases.map (·.render))
  ++ (if executionKnown then
        section' "未実行 TC (xunit 結果に不在)" (result.unexecutedTestCases.map (·.render))
      else ["未実行 TC: xunitPath 未設定のため判定省略"])

def runCrosscheck (registry : Registry) : IO UInt32 := do
  match ← loadConfig with
  | .error message =>
    IO.eprintln s!"idchain crosscheck: idchain.json の解析に失敗: {message}"
    return 2
  | .ok config =>
    let fileContents ← readTestFiles config
    let availability ← loadXunit config
    match availability with
    | .missing path =>
      IO.eprintln s!"idchain crosscheck: xunit 結果 {path} が存在しない (先に testCommand でテストを実行する)"
      return 2
    | .unconfigured =>
      let raw := crosscheck registry fileContents []
      let structural : CrosscheckResult :=
        { raw with orphanTests := [], unexecutedTestCases := [], failedTestCases := [], passedTestCases := [] }
      for line in renderCrosscheck structural false do
        IO.println line
      let clean := structural.unknownReferences.isEmpty && structural.unimplementedTestCases.isEmpty
      IO.println s!"idchain crosscheck (構造のみ): {if clean then "違反 0 件" else "違反あり"}"
      return (if clean then 0 else 1)
    | .loaded xunitCases =>
      let result := crosscheck registry fileContents xunitCases
      for line in renderCrosscheck result true do
        IO.println line
      IO.println s!"idchain crosscheck: 孤児テスト {result.orphanTests.length} 件 / 未知参照 {result.unknownReferences.length} 件 / 未実装 {result.unimplementedTestCases.length} 件 / 未実行 {result.unexecutedTestCases.length} 件"
      return (if result.isClean then 0 else 1)

def run (registry : Registry) (args : List String) : IO UInt32 := do
  match args with
  | ["check"] => runCheck registry
  | ["export"] => runExport registry
  | ["crosscheck"] => runCrosscheck registry
  | _ => do
    IO.eprintln "usage: idchain <check|export|crosscheck>   (views / report / approve / init は M1 実装中)"
    return 2

end Idchain.Cli
