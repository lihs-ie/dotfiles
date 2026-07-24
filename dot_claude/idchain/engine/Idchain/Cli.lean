import Idchain.Checks
import Idchain.Config
import Idchain.Export
import Idchain.Crosscheck
import Idchain.Views
import Idchain.Report
import Idchain.Approve
import Idchain.Init

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

def runViews (registry : Registry) (checkOnly : Bool) : IO UInt32 := do
  let rendered := views registry
  if checkOnly then
    let mut stale : List String := []
    for (name, content) in rendered do
      let path : System.FilePath := "views" / name
      let fresh ←
        if (← path.pathExists) then pure ((← IO.FS.readFile path) == content)
        else pure false
      if !fresh then
        stale := stale ++ [name]
    if stale.isEmpty then
      IO.println "idchain views --check: 全ビューが正本と一致 (鮮度 OK)"
      return 0
    else
      for name in stale do
        IO.println s!"STALE VIEW: views/{name} (正本と不一致。lake exe idchain views で再生成する)"
      return 1
  else
    IO.FS.createDirAll "views"
    for (name, content) in rendered do
      IO.FS.writeFile ("views" / name) content
    IO.println s!"idchain views: {rendered.length} ファイルを views/ に生成した"
    return 0

def runReport (registry : Registry) (date : String) : IO UInt32 := do
  match ← loadConfig with
  | .error message =>
    IO.eprintln s!"idchain report: idchain.json の解析に失敗: {message}"
    return 2
  | .ok config =>
    let fileContents ← readTestFiles config
    match ← loadXunit config with
    | .missing path =>
      IO.eprintln s!"idchain report: xunit 結果 {path} が存在しない (先に testCommand でテストを実行する)"
      return 2
    | availability =>
      let xunitCases := match availability with
        | .loaded cases => cases
        | _ => []
      let violations := registry.checkAll
      let result := crosscheck registry fileContents xunitCases
      let directory : System.FilePath := "reports" / date
      IO.FS.createDirAll directory
      IO.FS.writeFile (directory / "verification-report.md")
        (renderReportMarkdown date registry violations result)
      IO.FS.writeFile (directory / "verification-report.json")
        (renderReportJson date registry violations result)
      let verdicts := specVerdicts registry result
      let overall := overallPass violations result verdicts
      IO.println s!"idchain report: reports/{date}/ に生成 (総合判定: {if overall then "PASS" else "FAIL"})"
      return (if overall then 0 else 1)

def runApprove (registry : Registry) (args : List String) : IO UInt32 := do
  match args with
  | [target, "--by", approvedBy, "--note", note, "--date", date] =>
    match SimpleIdentifier.parse target with
    | none =>
      IO.eprintln s!"idchain approve: 不正な ID: {target}"
      return 2
    | some identifier =>
      match registry.contentHashFor identifier with
      | none =>
        IO.eprintln s!"idchain approve: 対象 {target} が正本に存在しない"
        return 2
      | some contentHash =>
        if !(← ("Canon" : System.FilePath).pathExists) then
          IO.eprintln "idchain approve: Canon/ が存在しない (対象 repo の idchain/ から実行する)"
          return 2
        let record : ApprovalRecord := ⟨identifier, { approvedBy, date, note, contentHash }⟩
        IO.FS.writeFile ("Canon" / "Approvals.lean")
          (renderApprovalsLean (upsertApproval registry.approvals record))
        IO.println s!"idchain approve: {target} を承認登録した (hash 0x{renderHash contentHash})"
        IO.println "commit message に idchain-approve を含めること (例: docs(idchain): approve SP-047 [idchain-approve])"
        return 0
  | _ =>
    IO.eprintln "usage: idchain approve <ID> --by <承認者> --note <判断根拠> --date <YYYY-MM-DD>"
    return 2

def runInitCommand (rest : List String) : IO UInt32 := do
  match ← Idchain.Init.detectEngineRoot with
  | none =>
    IO.eprintln "idchain init: engine root を検出できない (engine または対象 repo の idchain/ から実行する)"
    return 2
  | some engineRoot =>
    match rest with
    | [target] => Idchain.Init.runInit engineRoot target false
    | [target, "--update"] => Idchain.Init.runInit engineRoot target true
    | _ =>
      IO.eprintln "usage: idchain init <target-repo> [--update]"
      return 2

def run (registry : Registry) (args : List String) : IO UInt32 := do
  match args with
  | ["check"] => runCheck registry
  | ["export"] => runExport registry
  | ["crosscheck"] => runCrosscheck registry
  | ["views"] => runViews registry false
  | ["views", "--check"] => runViews registry true
  | ["report", "--date", date] => runReport registry date
  | "approve" :: rest => runApprove registry rest
  | "init" :: rest => runInitCommand rest
  | _ => do
    IO.eprintln "usage: idchain <check|export|crosscheck|views [--check]|report --date <YYYY-MM-DD>|approve <ID> --by <承認者> --note <根拠> --date <日付>|init <target-repo> [--update]>"
    return 2

end Idchain.Cli
