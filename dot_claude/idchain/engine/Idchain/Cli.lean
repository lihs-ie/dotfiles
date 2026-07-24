import Idchain.Checks
import Idchain.Config
import Idchain.Export
import Idchain.Crosscheck
import Idchain.Views
import Idchain.Report
import Idchain.Approve
import Idchain.Init
import Idchain.Oracle
import Idchain.Pairwise
import Idchain.Bench

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

/-- cwd の `oracle-results.json` があれば読み込む (`runOracle` の出力を `runReport` が拾う結線点)。 -/
def loadOracleResult : IO (Option OracleRunResult) := do
  let path : System.FilePath := "oracle-results.json"
  if (← path.pathExists) then
    match parseOracleResultsJson (← IO.FS.readFile path) with
    | .error message =>
      IO.eprintln s!"idchain report: oracle-results.json の解析に失敗: {message}"
      pure none
    | .ok result => pure (some result)
  else
    pure none

/-- cwd の `bench-results.json` があれば読み込む (`runBench` の出力を `runReport` が拾う結線点)。 -/
def loadBenchResult : IO (Option BenchRunResult) := do
  let path : System.FilePath := "bench-results.json"
  if (← path.pathExists) then
    match parseBenchResultsJson (← IO.FS.readFile path) with
    | .error message =>
      IO.eprintln s!"idchain report: bench-results.json の解析に失敗: {message}"
      pure none
    | .ok result => pure (some result)
  else
    pure none

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
      let oracleResult ← loadOracleResult
      let benchResult ← loadBenchResult
      let directory : System.FilePath := "reports" / date
      IO.FS.createDirAll directory
      IO.FS.writeFile (directory / "verification-report.md")
        (renderReportMarkdown date registry violations result oracleResult benchResult)
      IO.FS.writeFile (directory / "verification-report.json")
        (renderReportJson date registry violations result oracleResult benchResult)
      let verdicts := specVerdicts registry result
      let overall := overallPass violations result verdicts oracleResult benchResult
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

/-- registry.oracleQueries の testCase が正本に存在し kind = .oracle であるかの整合検査 (警告のみ、check の違反種別は増やさない)。 -/
def warnOracleQueryConsistency (registry : Registry) (oracleQuery : OracleQuery) : IO Unit := do
  match registry.testCases.find? (·.identifier == oracleQuery.testCase) with
  | none =>
    IO.println s!"警告: oracle クエリ {oracleQuery.testCase.render} に対応する TC が正本に存在しない"
  | some testCase =>
    if testCase.kind != TestCaseKind.oracle then
      IO.println s!"警告: {oracleQuery.testCase.render} は kind = oracle ではない TC を参照している"

/-- 1 クエリ × 1 エンジンを bash -c で実行し (trim 済) 出力を得る。実行エラーは特別な出力文字列で表す。 -/
def runOracleEngine (engine : OracleEngine) (query : String) : IO (String × String) := do
  let command := substituteQuery engine.command query
  try
    let result ← IO.Process.output { cmd := "bash", args := #["-c", command] }
    if result.exitCode == 0 then
      return (engine.name, trimWhitespace result.stdout)
    else
      return (engine.name, s!"<非ゼロ終了コード {result.exitCode}>")
  catch e =>
    return (engine.name, s!"<実行エラー: {e}>")

def runOracle (registry : Registry) : IO UInt32 := do
  match ← loadConfig with
  | .error message =>
    IO.eprintln s!"idchain oracle: idchain.json の解析に失敗: {message}"
    return 2
  | .ok config =>
    if registry.oracleQueries.isEmpty || config.oracleEngines.isEmpty then
      IO.println "oracle: 未設定のためスキップ"
      return 0
    else
      for oracleQuery in registry.oracleQueries do
        warnOracleQueryConsistency registry oracleQuery
      let mut queryResults : List OracleQueryResult := []
      let mut allAgreed := true
      for oracleQuery in registry.oracleQueries do
        let mut outputs : List (String × String) := []
        for engine in config.oracleEngines do
          outputs := outputs ++ [← runOracleEngine engine oracleQuery.query]
        let agreed := judgeOracle outputs
        if !agreed then allAgreed := false
        queryResults := queryResults ++ [{ testCase := oracleQuery.testCase, agreed, outputs }]
        IO.println s!"{oracleQuery.testCase.render}: {if agreed then "一致" else "不一致"}"
        for (name, output) in outputs do
          IO.println s!"  - {name}: {output}"
      let runResult : OracleRunResult := { queries := queryResults, allAgreed }
      IO.FS.writeFile "oracle-results.json" (renderOracleResultsJson runResult)
      if allAgreed then
        IO.println "idchain oracle: 全クエリ一致"
        return 0
      else
        IO.println "idchain oracle: 不一致あり"
        return 1

def runPairwise (registry : Registry) : IO UInt32 := do
  if registry.factors.length < 2 || registry.factors.any (·.levels.isEmpty) then
    IO.println "pairwise: 因子未定義のためスキップ"
    return 0
  else
    let configurations := generateConfigurations registry.factors
    let (coveredCount, totalCount) := coverage registry.factors configurations
    IO.println s!"| {String.intercalate " | " (registry.factors.map (·.name))} |"
    for configuration in configurations do
      IO.println s!"| {String.intercalate " | " configuration} |"
    if coveredCount != totalCount then
      IO.eprintln s!"idchain pairwise: 内部エラー — 網羅率 {coveredCount}/{totalCount} (100% ではない)"
      return 1
    else
      let directProductSize := registry.factors.foldl (fun acc factor => acc * factor.levels.length) 1
      IO.println s!"idchain pairwise: 2因子ペア網羅率 100% ({coveredCount}/{totalCount})、構成数 {configurations.length} (直積 {directProductSize} 通りから圧縮)"
      return 0

/-- 1 ベンチマークを bash -c で実行し判定する。実行エラー・parse 失敗は赤扱い (計測値 0)。 -/
def runOneBenchmark (benchmark : Benchmark) : IO BenchmarkResult := do
  try
    let output ← IO.Process.output { cmd := "bash", args := #["-c", benchmark.command] }
    match parseMilliseconds output.stdout with
    | some milliseconds =>
      pure { name := benchmark.name, milliseconds, judgement := judgeBenchmark benchmark milliseconds }
    | none =>
      IO.eprintln s!"idchain bench: {benchmark.name} の計測値 parse に失敗 (stdout: {trimWhitespace output.stdout})"
      pure { name := benchmark.name, milliseconds := 0, judgement := .red }
  catch e =>
    IO.eprintln s!"idchain bench: {benchmark.name} の実行エラー: {e}"
    pure { name := benchmark.name, milliseconds := 0, judgement := .red }

def runBench (registry : Registry) : IO UInt32 := do
  if registry.benchmarks.isEmpty then
    IO.println "bench: 未設定のためスキップ"
    return 0
  else
    let mut results : List BenchmarkResult := []
    for benchmark in registry.benchmarks do
      let result ← runOneBenchmark benchmark
      results := results ++ [result]
      IO.println s!"| {result.name} | {result.milliseconds}ms | green={benchmark.greenThresholdMilliseconds}/red={benchmark.redThresholdMilliseconds} | {result.judgement.label} |"
    let worst := worstJudgement (results.map (·.judgement))
    let runResult : BenchRunResult := { benchmarks := results, worst }
    IO.FS.writeFile "bench-results.json" (renderBenchResultsJson runResult)
    if worst == BenchmarkJudgement.red then
      IO.println "idchain bench: 赤判定あり"
      return 1
    else
      IO.println s!"idchain bench: 総合判定 {worst.label}"
      return 0

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
  | ["oracle"] => runOracle registry
  | ["pairwise"] => runPairwise registry
  | ["bench"] => runBench registry
  | "approve" :: rest => runApprove registry rest
  | "init" :: rest => runInitCommand rest
  | _ => do
    IO.eprintln "usage: idchain <check|export|crosscheck|views [--check]|report --date <YYYY-MM-DD>|oracle|pairwise|bench|approve <ID> --by <承認者> --note <根拠> --date <日付>|init <target-repo> [--update]>"
    return 2

end Idchain.Cli
