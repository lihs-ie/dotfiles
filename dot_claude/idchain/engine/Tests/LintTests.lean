import Idchain.Lint
import Idchain.Registry
import Tests.Framework

/-! Must-25: 曖昧語 lint (lintSpecs) のテスト。ヒットする SP / しない SP を確認する。 -/

namespace Idchain.Tests.LintTests

open Idchain

def specHit : Spec := ⟨1, "計測値は正の値であることが適切に判定されること", 1⟩
def specClean : Spec := ⟨2, "計測値は 0 以上の整数であり、上限値は 100 である", 1⟩

def registryHit : Registry := { Registry.empty with specs := [specHit] }
def registryClean : Registry := { Registry.empty with specs := [specClean] }
def registryMixed : Registry := { Registry.empty with specs := [specHit, specClean] }

private def anyMessageContains (hits : List (String × String)) (needle : String) : Bool :=
  hits.any fun (_, message) => (message.splitOn needle).length > 1

def hitCases : List TestResult := [
  check "曖昧語「正の値」がヒットする" (anyMessageContains (lintSpecs registryHit) "正の値"),
  check "曖昧語「適切」がヒットする" (anyMessageContains (lintSpecs registryHit) "適切"),
  check "ヒットは SP-001 に紐づく" ((lintSpecs registryHit).any (fun (id, _) => id == "SP-001")),
  check "1 SP から複数語ヒットしうる" ((lintSpecs registryHit).length ≥ 2),
  check "曖昧語を含まない SP はヒットしない" (lintSpecs registryClean == []),
  check "曖昧語を含む SP のみがヒットする (混在 registry)"
    ((lintSpecs registryMixed).all (fun (id, _) => id == "SP-001"))
]

def suite : String × List TestResult :=
  ("LintTests (Must-25)", hitCases)

end Idchain.Tests.LintTests
