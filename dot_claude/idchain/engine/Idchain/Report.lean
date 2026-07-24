import Lean.Data.Json
import Idchain.Checks
import Idchain.Crosscheck
import Idchain.Views

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
    let testCases := (registry.testCases.filter (·.identifier.spec == spec.number)).map (·.identifier)
    let approved := registry.isApproved ⟨.sp, spec.number⟩
    let failed := testCases.filter (result.failedTestCases.contains ·)
    let missing := testCases.filter fun testCase =>
      result.unimplementedTestCases.contains testCase ||
      result.unexecutedTestCases.contains testCase
    let executed := testCases.filter fun testCase =>
      result.passedTestCases.contains testCase || result.failedTestCases.contains testCase
    { spec, approved, testCases, failed, missing
      verified := !executed.isEmpty
      passed := approved && !testCases.isEmpty && failed.isEmpty && missing.isEmpty &&
        testCases.all (result.passedTestCases.contains ·) }

/-- 検証に紐づいていない仕様 (承認済かつ実行済 TC を持つ、が成立しない仕様) の数。 -/
def unchainedSpecCount (verdicts : List SpecVerdict) : Nat :=
  (verdicts.filter fun verdict => !(verdict.approved && verdict.verified)).length

def overallPass (violations : List Violation) (result : CrosscheckResult)
    (verdicts : List SpecVerdict) : Bool :=
  violations.isEmpty && result.isClean && result.failedTestCases.isEmpty &&
  verdicts.all (·.passed)

def renderReportMarkdown (date : String) (registry : Registry)
    (violations : List Violation) (result : CrosscheckResult) : String :=
  let verdicts := specVerdicts registry result
  let overall := overallPass violations result verdicts
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
    ["", "## 違反一覧", ""] ++ violationLines)

open Lean (Json) in
def renderReportJson (date : String) (registry : Registry)
    (violations : List Violation) (result : CrosscheckResult) : String :=
  let verdicts := specVerdicts registry result
  (Json.mkObj [
    ("date", Json.str date),
    ("overall", Json.str (if overallPass violations result verdicts then "PASS" else "FAIL")),
    ("unchainedSpecs", Json.num ⟨(unchainedSpecCount verdicts : Int), 0⟩),
    ("orphanTests", Json.num ⟨(result.orphanTests.length : Int), 0⟩),
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
