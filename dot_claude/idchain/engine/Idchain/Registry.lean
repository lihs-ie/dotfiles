import Idchain.Approval

/-!
# Registry (正本の集約、データ層)

対象 repo の `Canon/*.lean` が構築する全アーティファクトの集約。
exe はこのデータ層のみを実行時に処理する (SP の形式的意味は `Idchain.Semantics`)。
-/

namespace Idchain

structure Registry where
  problems : List Problem
  values : List Value
  featureAreas : List FeatureArea
  hypotheses : List Hypothesis
  specs : List Spec
  testCases : List TestCase
  learnings : List Learning
  approvals : List ApprovalRecord
  /-- 再利用禁止台帳: 退役した ID。ここにある番号は同種アーティファクトで再登場してはならない。 -/
  retired : List SimpleIdentifier
  /-- オラクル突合の対象クエリ (M3)。既存 canon リテラルを壊さないよう既定は空。 -/
  oracleQueries : List OracleQuery := []
  /-- ペアワイズ生成の因子一覧 (M3)。既定は空。 -/
  factors : List Factor := []
  /-- ベンチマーク定義一覧 (M3)。既定は空。 -/
  benchmarks : List Benchmark := []
  deriving Repr, Inhabited

def Registry.empty : Registry :=
  { problems := [], values := [], featureAreas := [], hypotheses := [], specs := [],
    testCases := [], learnings := [], approvals := [], retired := [] }

def Registry.findProblem (registry : Registry) (number : Nat) : Option Problem :=
  registry.problems.find? (·.number == number)

def Registry.findValue (registry : Registry) (number : Nat) : Option Value :=
  registry.values.find? (·.number == number)

def Registry.findFeatureArea (registry : Registry) (number : Nat) : Option FeatureArea :=
  registry.featureAreas.find? (·.number == number)

def Registry.findHypothesis (registry : Registry) (number : Nat) : Option Hypothesis :=
  registry.hypotheses.find? (·.number == number)

def Registry.findSpec (registry : Registry) (number : Nat) : Option Spec :=
  registry.specs.find? (·.number == number)

def Registry.findLearning (registry : Registry) (number : Nat) : Option Learning :=
  registry.learnings.find? (·.number == number)

/-- 対象 ID の現内容ハッシュ (承認鮮度検査用)。 -/
def Registry.contentHashFor (registry : Registry) (identifier : SimpleIdentifier) : Option UInt64 :=
  match identifier.kind with
  | .pb => (registry.findProblem identifier.number).map contentHashOf
  | .vl => (registry.findValue identifier.number).map contentHashOf
  | .fa => (registry.findFeatureArea identifier.number).map contentHashOf
  | .hy => (registry.findHypothesis identifier.number).map contentHashOf
  | .sp => (registry.findSpec identifier.number).map contentHashOf
  | .ll => (registry.findLearning identifier.number).map contentHashOf

/-- fresh な承認 (ハッシュが現内容と一致) を持つか。 -/
def Registry.isApproved (registry : Registry) (identifier : SimpleIdentifier) : Bool :=
  registry.approvals.any fun record =>
    record.target == identifier &&
      (registry.contentHashFor identifier).any (record.approval.contentHash == ·)

end Idchain
