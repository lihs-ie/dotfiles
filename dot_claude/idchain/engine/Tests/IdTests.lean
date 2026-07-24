import Idchain.Id
import Tests.Framework

/-! U1: ID 型の render / parse / 往復同一性テスト。 -/

namespace Idchain.Tests.IdTests

open Idchain

def renderCases : List TestResult := [
  checkEq "SP-047 render" (SimpleId.render ⟨.sp, 47⟩) "SP-047",
  checkEq "PB-001 render" (SimpleId.render ⟨.pb, 1⟩) "PB-001",
  checkEq "LL-999 render" (SimpleId.render ⟨.ll, 999⟩) "LL-999",
  checkEq "FA-1000 render (4桁はそのまま)" (SimpleId.render ⟨.fa, 1000⟩) "FA-1000",
  checkEq "HY-000 render (0 も機械的に描画)" (SimpleId.render ⟨.hy, 0⟩) "HY-000",
  checkEq "TC-047-1 render" (TestCaseId.render ⟨47, 1⟩) "TC-047-1",
  checkEq "TC-047-12 render (枝番はゼロ埋めなし)" (TestCaseId.render ⟨47, 12⟩) "TC-047-12",
  checkEq "TC-1047-3 render" (TestCaseId.render ⟨1047, 3⟩) "TC-1047-3"
]

def parseValidCases : List TestResult := [
  checkEq "SP-047 parse" (SimpleId.parse "SP-047") (some ⟨.sp, 47⟩),
  checkEq "VL-003 parse" (SimpleId.parse "VL-003") (some ⟨.vl, 3⟩),
  checkEq "FA-1000 parse" (SimpleId.parse "FA-1000") (some ⟨.fa, 1000⟩),
  checkEq "TC-047-1 parse" (TestCaseId.parse "TC-047-1") (some ⟨47, 1⟩),
  checkEq "TC-047-12 parse" (TestCaseId.parse "TC-047-12") (some ⟨47, 12⟩),
  checkEq "AnyId simple dispatch" (AnyId.parse "SP-047") (some (.simple ⟨.sp, 47⟩)),
  checkEq "AnyId testCase dispatch" (AnyId.parse "TC-047-2") (some (.testCase ⟨47, 2⟩))
]

def parseRejectCases : List TestResult := [
  checkEq "SP-47 (ゼロ埋め不足) 拒否" (SimpleId.parse "SP-47") (none : Option SimpleId),
  checkEq "SP-0470 (冗長ゼロ埋め) 拒否" (SimpleId.parse "SP-0470") (none : Option SimpleId),
  checkEq "sp-047 (小文字) 拒否" (SimpleId.parse "sp-047") (none : Option SimpleId),
  checkEq "XX-001 (未知プレフィックス) 拒否" (SimpleId.parse "XX-001") (none : Option SimpleId),
  checkEq "SP001 (区切りなし) 拒否" (SimpleId.parse "SP001") (none : Option SimpleId),
  checkEq "SP-047-1 (単純IDに枝番) 拒否" (SimpleId.parse "SP-047-1") (none : Option SimpleId),
  checkEq "SP-04a (非数字) 拒否" (SimpleId.parse "SP-04a") (none : Option SimpleId),
  checkEq "空文字列 拒否" (SimpleId.parse "") (none : Option SimpleId),
  checkEq "TC-047 (枝番欠落) 拒否" (TestCaseId.parse "TC-047") (none : Option TestCaseId),
  checkEq "TC-47-1 (SP側ゼロ埋め不足) 拒否" (TestCaseId.parse "TC-47-1") (none : Option TestCaseId),
  checkEq "TC-047-01 (枝番ゼロ埋め) 拒否" (TestCaseId.parse "TC-047-01") (none : Option TestCaseId),
  checkEq "TC-047- (枝番空) 拒否" (TestCaseId.parse "TC-047-") (none : Option TestCaseId),
  checkEq "SP-047 は TC として拒否" (TestCaseId.parse "SP-047") (none : Option TestCaseId),
  checkEq "TC-047-1 は SimpleId として拒否" (SimpleId.parse "TC-047-1") (none : Option SimpleId)
]

def roundtripNumbers : List Nat := [0, 1, 46, 47, 99, 100, 999, 1000, 1234]

def simpleRoundtrip : List TestResult :=
  ArtifactKind.all.flatMap fun kind =>
    roundtripNumbers.map fun n =>
      let id : SimpleId := ⟨kind, n⟩
      checkEq s!"roundtrip {id.render}" (SimpleId.parse id.render) (some id)

def testCaseRoundtrip : List TestResult :=
  roundtripNumbers.flatMap fun spec =>
    [1, 2, 12, 120].map fun branch =>
      let id : TestCaseId := ⟨spec, branch⟩
      checkEq s!"roundtrip {id.render}" (TestCaseId.parse id.render) (some id)

def suite : String × List TestResult :=
  ("IdTests (U1)",
    renderCases ++ parseValidCases ++ parseRejectCases ++ simpleRoundtrip ++ testCaseRoundtrip)

end Idchain.Tests.IdTests
