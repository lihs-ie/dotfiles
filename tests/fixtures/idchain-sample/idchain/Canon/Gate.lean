import Canon.Artifacts
import Canon.Approvals
import Canon.SemanticReviews

/-! 無矛盾性ゲート: witness = 明細 [1,2,3]・小計 6。証明が閉じない限りビルド不能。 -/

namespace Canon

open Idchain

def registry : Registry := {
  problems := problems
  values := values
  featureAreas := featureAreas
  hypotheses := hypotheses
  specs := specs
  testCases := testCases
  learnings := learnings
  approvals := approvals
  retired := retired
  oracleQueries := oracleQueries
  factors := factors
  benchmarks := benchmarks
  roadmapItems := roadmapItems
  semanticReviews := semanticReviews
}

def gate : ConsistencyProof Model registry interpretations := {
  witness := ⟨[1, 2, 3], 6⟩
  sound := by
    intro interpretation mem
    simp [interpretations] at mem
    subst mem
    rfl
  complete := by decide
}

end Canon
