import Canon.Artifacts
import Canon.Approvals

/-! 無矛盾性ゲート (負例 fixture): 全 SP の解釈を trivially 満たすだけの witness。 -/

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
  benchmarks := benchmarks
}

def gate : ConsistencyProof Model registry interpretations := {
  witness := {}
  sound := by intro interpretation mem; simp [interpretations] at mem; rcases mem with rfl | rfl <;> trivial
  complete := by decide
}

end Canon
