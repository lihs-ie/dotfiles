import Idchain.Identifier
import Tests.Framework

/-! U1: ID 型の render / parse / 往復同一性テスト。 -/

namespace Idchain.Tests.IdentifierTests

open Idchain

def renderCases : List TestResult := [
  checkEq "SP-047 render" (SimpleIdentifier.render ⟨.sp, 47⟩) "SP-047",
  checkEq "PB-001 render" (SimpleIdentifier.render ⟨.pb, 1⟩) "PB-001",
  checkEq "LL-999 render" (SimpleIdentifier.render ⟨.ll, 999⟩) "LL-999",
  checkEq "FA-1000 render (4桁はそのまま)" (SimpleIdentifier.render ⟨.fa, 1000⟩) "FA-1000",
  checkEq "HY-000 render (0 も機械的に描画)" (SimpleIdentifier.render ⟨.hy, 0⟩) "HY-000",
  checkEq "TC-047-1 render" (TestCaseIdentifier.render ⟨47, 1⟩) "TC-047-1",
  checkEq "TC-047-12 render (枝番はゼロ埋めなし)" (TestCaseIdentifier.render ⟨47, 12⟩) "TC-047-12",
  checkEq "TC-1047-3 render" (TestCaseIdentifier.render ⟨1047, 3⟩) "TC-1047-3"
]

def parseValidCases : List TestResult := [
  checkEq "SP-047 parse" (SimpleIdentifier.parse "SP-047") (some ⟨.sp, 47⟩),
  checkEq "VL-003 parse" (SimpleIdentifier.parse "VL-003") (some ⟨.vl, 3⟩),
  checkEq "FA-1000 parse" (SimpleIdentifier.parse "FA-1000") (some ⟨.fa, 1000⟩),
  checkEq "TC-047-1 parse" (TestCaseIdentifier.parse "TC-047-1") (some ⟨47, 1⟩),
  checkEq "TC-047-12 parse" (TestCaseIdentifier.parse "TC-047-12") (some ⟨47, 12⟩),
  checkEq "AnyIdentifier simple dispatch" (AnyIdentifier.parse "SP-047") (some (.simple ⟨.sp, 47⟩)),
  checkEq "AnyIdentifier testCase dispatch" (AnyIdentifier.parse "TC-047-2") (some (.testCase ⟨47, 2⟩))
]

def parseRejectCases : List TestResult := [
  checkEq "SP-47 (ゼロ埋め不足) 拒否" (SimpleIdentifier.parse "SP-47") (none : Option SimpleIdentifier),
  checkEq "SP-0470 (冗長ゼロ埋め) 拒否" (SimpleIdentifier.parse "SP-0470") (none : Option SimpleIdentifier),
  checkEq "sp-047 (小文字) 拒否" (SimpleIdentifier.parse "sp-047") (none : Option SimpleIdentifier),
  checkEq "XX-001 (未知プレフィックス) 拒否" (SimpleIdentifier.parse "XX-001") (none : Option SimpleIdentifier),
  checkEq "SP001 (区切りなし) 拒否" (SimpleIdentifier.parse "SP001") (none : Option SimpleIdentifier),
  checkEq "SP-047-1 (単純IDに枝番) 拒否" (SimpleIdentifier.parse "SP-047-1") (none : Option SimpleIdentifier),
  checkEq "SP-04a (非数字) 拒否" (SimpleIdentifier.parse "SP-04a") (none : Option SimpleIdentifier),
  checkEq "空文字列 拒否" (SimpleIdentifier.parse "") (none : Option SimpleIdentifier),
  checkEq "TC-047 (枝番欠落) 拒否" (TestCaseIdentifier.parse "TC-047") (none : Option TestCaseIdentifier),
  checkEq "TC-47-1 (SP側ゼロ埋め不足) 拒否" (TestCaseIdentifier.parse "TC-47-1") (none : Option TestCaseIdentifier),
  checkEq "TC-047-01 (枝番ゼロ埋め) 拒否" (TestCaseIdentifier.parse "TC-047-01") (none : Option TestCaseIdentifier),
  checkEq "TC-047- (枝番空) 拒否" (TestCaseIdentifier.parse "TC-047-") (none : Option TestCaseIdentifier),
  checkEq "SP-047 は TC として拒否" (TestCaseIdentifier.parse "SP-047") (none : Option TestCaseIdentifier),
  checkEq "TC-047-1 は SimpleIdentifier として拒否" (SimpleIdentifier.parse "TC-047-1") (none : Option SimpleIdentifier)
]

def roundtripNumbers : List Nat := [0, 1, 46, 47, 99, 100, 999, 1000, 1234]

def simpleRoundtrip : List TestResult :=
  ArtifactKind.all.flatMap fun kind =>
    roundtripNumbers.map fun n =>
      let identifier : SimpleIdentifier := ⟨kind, n⟩
      checkEq s!"roundtrip {identifier.render}" (SimpleIdentifier.parse identifier.render) (some identifier)

def testCaseRoundtrip : List TestResult :=
  roundtripNumbers.flatMap fun spec =>
    [1, 2, 12, 120].map fun branch =>
      let identifier : TestCaseIdentifier := ⟨spec, branch⟩
      checkEq s!"roundtrip {identifier.render}" (TestCaseIdentifier.parse identifier.render) (some identifier)

def suite : String × List TestResult :=
  ("IdentifierTests (U1)",
    renderCases ++ parseValidCases ++ parseRejectCases ++ simpleRoundtrip ++ testCaseRoundtrip)

end Idchain.Tests.IdentifierTests
