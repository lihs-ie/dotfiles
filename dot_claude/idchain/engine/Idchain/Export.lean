import Lean.Data.Json
import Idchain.Registry

/-!
# JSON export (U7)

TC 一覧と ID inventory の機械可読出力。外部ツール連携と検証レポートの素材。
-/

namespace Idchain

open Lean (Json)

def TestCaseKind.jsonString : TestCaseKind → String
  | .example => "example"
  | .property => "property"
  | .oracle => "oracle"
  | .regression => "regression"

def exportJson (registry : Registry) : String :=
  let testCases := registry.testCases.map fun testCase => Json.mkObj [
    ("id", Json.str testCase.identifier.render),
    ("spec", Json.str (SimpleIdentifier.render ⟨.sp, testCase.identifier.spec⟩)),
    ("branch", Json.num ⟨(testCase.identifier.branch : Int), 0⟩),
    ("description", Json.str testCase.description),
    ("kind", Json.str testCase.kind.jsonString)]
  let renderAll (kind : ArtifactKind) (numbers : List Nat) : List Json :=
    numbers.map fun number => Json.str (SimpleIdentifier.render ⟨kind, number⟩)
  let identifiers :=
    renderAll .pb (registry.problems.map (·.number)) ++
    renderAll .vl (registry.values.map (·.number)) ++
    renderAll .fa (registry.featureAreas.map (·.number)) ++
    renderAll .hy (registry.hypotheses.map (·.number)) ++
    renderAll .sp (registry.specs.map (·.number)) ++
    renderAll .ll (registry.learnings.map (·.number))
  (Json.mkObj [
    ("testCases", Json.arr testCases.toArray),
    ("identifiers", Json.arr identifiers.toArray)]).pretty

end Idchain
