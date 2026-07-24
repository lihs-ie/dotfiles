import Lean.Data.Json
import Idchain.Checks
import Idchain.Crosscheck
import Idchain.Views
import Idchain.Oracle
import Idchain.Bench

/-!
# 検証レポート生成 (U10、発表 p.37)

check (トレーサビリティ) + crosscheck (TC⇄テスト突合) + テスト成否から
SP 毎の PASS/FAIL と「検証に紐づいていない仕様 N 件 / 仕様に紐づいていないテスト N 件」を刻む。
-/

namespace Idchain

structure SpecVerdict where
  spec : Spec
  approved : Bool
  testCases : List TestCaseIdentifier
  failed : List TestCaseIdentifier
  missing : List TestCaseIdentifier
  verified : Bool
  passed : Bool
  deriving Repr, Inhabited

def specVerdicts (registry : Registry) (result : CrosscheckResult) : List SpecVerdict :=
  registry.specs.map fun spec =>
    let specTestCases := registry.testCases.filter (·.identifier.spec == spec.number)
    let testCases := specTestCases.map (·.identifier)
    -- kind = .oracle の TC は oracle exe で検証されるため、crosscheck (xunit) 由来の
    -- 合否判定からは除外する (`Idchain.Crosscheck` の canonIdentifiers 除外と対応)。
    let verifiableTestCases := (specTestCases.filter (·.kind != TestCaseKind.oracle)).map (·.identifier)
    let approved := registry.isApproved ⟨.sp, spec.number⟩
    let failed := verifiableTestCases.filter (result.failedTestCases.contains ·)
    let missing := verifiableTestCases.filter fun testCase =>
      result.unimplementedTestCases.contains testCase ||
      result.unexecutedTestCases.contains testCase
    let executed := verifiableTestCases.filter fun testCase =>
      result.passedTestCases.contains testCase || result.failedTestCases.contains testCase
    { spec, approved, testCases, failed, missing
      verified := !executed.isEmpty
      passed := approved && !testCases.isEmpty && failed.isEmpty && missing.isEmpty &&
        verifiableTestCases.all (result.passedTestCases.contains ·) }

/-- 検証に紐づいていない仕様 (承認済かつ実行済 TC を持つ、が成立しない仕様) の数。 -/
def unchainedSpecCount (verdicts : List SpecVerdict) : Nat :=
  (verdicts.filter fun verdict => !(verdict.approved && verdict.verified)).length

/-- oracle 未実施 (none) は判定に影響させない (graceful skip)。実施済で不一致なら FAIL。 -/
private def oracleOk (oracleResult : Option OracleRunResult) : Bool :=
  match oracleResult with
  | none => true
  | some result => result.allAgreed

/-- bench 未実施 (none) は判定に影響させない。実施済で worst = red なら FAIL。 -/
private def benchOk (benchResult : Option BenchRunResult) : Bool :=
  match benchResult with
  | none => true
  | some result => result.worst != .red

def overallPass (violations : List Violation) (result : CrosscheckResult)
    (verdicts : List SpecVerdict) (oracleResult : Option OracleRunResult := none)
    (benchResult : Option BenchRunResult := none) : Bool :=
  violations.isEmpty && result.isClean && result.failedTestCases.isEmpty &&
  verdicts.all (·.passed) && oracleOk oracleResult && benchOk benchResult

/-- 「## オラクル突合」セクション。未実施は「未実施」とだけ記載する (graceful skip)。 -/
private def renderOracleSection (oracleResult : Option OracleRunResult) : List String :=
  match oracleResult with
  | none => ["## オラクル突合", "", "未実施", ""]
  | some result =>
    let rows := result.queries.map fun queryResult =>
      let outputCells := queryResult.outputs.map fun (engine, output) => s!"{engine}={output}"
      s!"| {queryResult.testCase.render} | {if queryResult.agreed then "一致 ✓" else "不一致 ✗"} | {String.intercalate "、" outputCells} |"
    ["## オラクル突合", "",
     s!"- 総合判定: {if result.allAgreed then "全クエリ一致" else "不一致あり"}", "",
     "| クエリ | 判定 | 各エンジン出力 |", "|---|---|---|"] ++ rows ++ [""]

/-- 「## ベンチマーク」セクション。未実施は「未実施」とだけ記載する (graceful skip)。 -/
private def renderBenchSection (benchResult : Option BenchRunResult) : List String :=
  match benchResult with
  | none => ["## ベンチマーク", "", "未実施", ""]
  | some result =>
    let rows := result.benchmarks.map fun benchmarkResult =>
      s!"| {benchmarkResult.name} | {benchmarkResult.milliseconds}ms | {benchmarkResult.judgement.label} |"
    ["## ベンチマーク", "",
     s!"- 総合判定: {result.worst.label}", "",
     "| ベンチマーク | 計測値 | 判定 |", "|---|---|---|"] ++ rows ++ [""]

def renderReportMarkdown (date : String) (registry : Registry)
    (violations : List Violation) (result : CrosscheckResult)
    (oracleResult : Option OracleRunResult := none)
    (benchResult : Option BenchRunResult := none) : String :=
  let verdicts := specVerdicts registry result
  let overall := overallPass violations result verdicts oracleResult benchResult
  let verdictRows := verdicts.map fun verdict =>
    let mark := if verdict.passed then "PASS ✓" else "FAIL ✗"
    let testCaseCells := verdict.testCases.map fun testCase =>
      if result.passedTestCases.contains testCase then s!"{testCase.render} ✓"
      else if result.failedTestCases.contains testCase then s!"{testCase.render} ✗"
      else s!"{testCase.render}（未実行）"
    s!"| {SimpleIdentifier.render ⟨.sp, verdict.spec.number⟩} {verdict.spec.text} | {mark} | {String.intercalate "、" testCaseCells} |"
  let violationLines :=
    if violations.isEmpty then ["- なし"]
    else violations.map fun violation =>
      s!"- [{violation.kind.label}] {violation.identifier}: {violation.message}"
  joinLines (
    [s!"# 検証レポート ({date})", "",
     s!"## 総合判定: {if overall then "PASS" else "FAIL"}", "",
     s!"- 検証に紐づいていない仕様: {unchainedSpecCount verdicts} 件",
     s!"- 仕様に紐づいていないテスト: {result.orphanTests.length} 件",
     s!"- トレーサビリティ違反: {violations.length} 件",
     s!"- テスト失敗: {result.failedTestCases.length} 件", "",
     "## 仕様別判定", "",
     "| 仕様 | 判定 | テストケース |", "|---|---|---|"] ++ verdictRows ++
    ["", "## 違反一覧", ""] ++ violationLines ++
    [""] ++ renderOracleSection oracleResult ++ renderBenchSection benchResult)

open Lean (Json) in
private def oracleResultJson (oracleResult : Option OracleRunResult) : Json :=
  match oracleResult with
  | none => Json.mkObj [("status", Json.str "未実施")]
  | some result => Json.mkObj [
      ("status", Json.str "実施済"),
      ("allAgreed", Json.bool result.allAgreed),
      ("queries", Json.arr (result.queries.map fun queryResult => Json.mkObj [
        ("testCase", Json.str queryResult.testCase.render),
        ("agreed", Json.bool queryResult.agreed)]).toArray)]

open Lean (Json) in
private def benchResultJson (benchResult : Option BenchRunResult) : Json :=
  match benchResult with
  | none => Json.mkObj [("status", Json.str "未実施")]
  | some result => Json.mkObj [
      ("status", Json.str "実施済"),
      ("worst", Json.str result.worst.label),
      ("benchmarks", Json.arr (result.benchmarks.map fun benchmarkResult => Json.mkObj [
        ("name", Json.str benchmarkResult.name),
        ("milliseconds", Json.num ⟨(benchmarkResult.milliseconds : Int), 0⟩),
        ("judgement", Json.str benchmarkResult.judgement.label)]).toArray)]

open Lean (Json) in
def renderReportJson (date : String) (registry : Registry)
    (violations : List Violation) (result : CrosscheckResult)
    (oracleResult : Option OracleRunResult := none)
    (benchResult : Option BenchRunResult := none) : String :=
  let verdicts := specVerdicts registry result
  (Json.mkObj [
    ("date", Json.str date),
    ("overall", Json.str
      (if overallPass violations result verdicts oracleResult benchResult then "PASS" else "FAIL")),
    ("unchainedSpecs", Json.num ⟨(unchainedSpecCount verdicts : Int), 0⟩),
    ("orphanTests", Json.num ⟨(result.orphanTests.length : Int), 0⟩),
    ("oracle", oracleResultJson oracleResult),
    ("bench", benchResultJson benchResult),
    ("violations", Json.arr (violations.map fun violation => Json.mkObj [
      ("kind", Json.str violation.kind.label),
      ("identifier", Json.str violation.identifier),
      ("message", Json.str violation.message)]).toArray),
    ("specs", Json.arr (verdicts.map fun verdict => Json.mkObj [
      ("id", Json.str (SimpleIdentifier.render ⟨.sp, verdict.spec.number⟩)),
      ("approved", Json.bool verdict.approved),
      ("passed", Json.bool verdict.passed),
      ("testCases", Json.arr (verdict.testCases.map fun testCase =>
        Json.str testCase.render).toArray)]).toArray)
  ]).pretty

end Idchain
