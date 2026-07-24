import Idchain.Registry

/-!
# トレーサビリティ決定論的検査 (発表 p.41「やったかは常時・全件を機械判定」)

全検査は決定可能な計算 = 計算による証明。違反ゼロで「ID の鎖」が閉じていることが機械的に保証される
(発表 p.37: 検証に紐づいていない仕様 0 件 / 仕様に紐づいていないテスト 0 件)。

LL の append-only 性について: スナップショット単体では末尾削除を検出できないため、
静的検査は連番充足 (1..N 欠番なし) までを保証し、削除検出は CI の履歴比較 (M2) が補完する。
-/

namespace Idchain

inductive ViolationKind where
  | invalidNumber
  | duplicateIdentifier
  | duplicateTestCase
  | retiredIdentifierReuse
  | valueWithoutProblem
  | featureAreaWithoutValue
  | specWithoutFeatureArea
  | hypothesisWithoutAnchor
  | testCaseWithoutSpec
  | testCaseForUnapprovedSpec
  | orphanSpec
  | staleApproval
  | approvalTargetMissing
  | learningNotContiguous
  deriving Repr, DecidableEq, Inhabited

def ViolationKind.label : ViolationKind → String
  | .invalidNumber => "invalid-number"
  | .duplicateIdentifier => "duplicate-identifier"
  | .duplicateTestCase => "duplicate-test-case"
  | .retiredIdentifierReuse => "retired-identifier-reuse"
  | .valueWithoutProblem => "value-without-problem"
  | .featureAreaWithoutValue => "feature-area-without-value"
  | .specWithoutFeatureArea => "spec-without-feature-area"
  | .hypothesisWithoutAnchor => "hypothesis-without-anchor"
  | .testCaseWithoutSpec => "test-case-without-spec"
  | .testCaseForUnapprovedSpec => "test-case-for-unapproved-spec"
  | .orphanSpec => "orphan-spec"
  | .staleApproval => "stale-approval"
  | .approvalTargetMissing => "approval-target-missing"
  | .learningNotContiguous => "learning-not-contiguous"

structure Violation where
  kind : ViolationKind
  identifier : String
  message : String
  deriving Repr, Inhabited

private def violation (kind : ViolationKind) (identifier : String) (message : String) : Violation :=
  ⟨kind, identifier, message⟩

private def duplicatesIn [BEq α] (items : List α) : List α :=
  (items.filter fun item => (items.filter (· == item)).length > 1).eraseDups

private def numbersOf (registry : Registry) (kind : ArtifactKind) : List Nat :=
  match kind with
  | .pb => registry.problems.map (·.number)
  | .vl => registry.values.map (·.number)
  | .fa => registry.featureAreas.map (·.number)
  | .hy => registry.hypotheses.map (·.number)
  | .sp => registry.specs.map (·.number)
  | .ll => registry.learnings.map (·.number)

private def checkNumbers (registry : Registry) : List Violation :=
  (ArtifactKind.all.flatMap fun kind =>
    ((numbersOf registry kind).filter (· == 0)).map fun _ =>
      violation .invalidNumber s!"{kind.prefixString}-000" "ID 番号は 1 以上でなければならない")
  ++ (registry.testCases.filter fun tc => tc.identifier.spec == 0 || tc.identifier.branch == 0).map
      (fun tc => violation .invalidNumber tc.identifier.render "TC の SP 番号・枝番は 1 以上でなければならない")

private def checkDuplicates (registry : Registry) : List Violation :=
  (ArtifactKind.all.flatMap fun kind =>
    (duplicatesIn (numbersOf registry kind)).map fun number =>
      violation .duplicateIdentifier (SimpleIdentifier.render ⟨kind, number⟩) "ID が重複している")
  ++ (duplicatesIn (registry.testCases.map (·.identifier))).map fun identifier =>
      violation .duplicateTestCase identifier.render "TC ID が重複している"

private def checkRetired (registry : Registry) : List Violation :=
  registry.retired.filter (fun identifier => (numbersOf registry identifier.kind).contains identifier.number)
    |>.map fun identifier =>
      violation .retiredIdentifierReuse identifier.render "退役済み ID の再利用は禁止"

private def checkValues (registry : Registry) : List Violation :=
  registry.values.filter (fun value => (registry.findProblem value.problem).isNone)
    |>.map fun value =>
      violation .valueWithoutProblem (SimpleIdentifier.render ⟨.vl, value.number⟩)
        s!"対応する課題 PB-{padNumber value.problem} が存在しない (価値は課題とペアで書く)"

private def checkFeatureAreas (registry : Registry) : List Violation :=
  registry.featureAreas.filter
      (fun featureArea => featureArea.values.isEmpty ||
        featureArea.values.any (fun number => (registry.findValue number).isNone))
    |>.map fun featureArea =>
      violation .featureAreaWithoutValue (SimpleIdentifier.render ⟨.fa, featureArea.number⟩)
        "参照する提供価値 VL が空または不在 (What と How を繋ぐ)"

private def checkSpecs (registry : Registry) : List Violation :=
  registry.specs.filter (fun spec => (registry.findFeatureArea spec.featureArea).isNone)
    |>.map fun spec =>
      violation .specWithoutFeatureArea (SimpleIdentifier.render ⟨.sp, spec.number⟩)
        s!"帰属する機能領域 FA-{padNumber spec.featureArea} が存在しない"

private def checkHypotheses (registry : Registry) : List Violation :=
  registry.hypotheses.filter
      (fun hypothesis => hypothesis.problems.isEmpty ||
        hypothesis.problems.any (fun number => (registry.findProblem number).isNone))
    |>.map fun hypothesis =>
      violation .hypothesisWithoutAnchor (SimpleIdentifier.render ⟨.hy, hypothesis.number⟩)
        "仮説が課題 PB に接続されていない"

private def checkTestCases (registry : Registry) : List Violation :=
  registry.testCases.flatMap fun testCase =>
    match registry.findSpec testCase.identifier.spec with
    | none =>
      [violation .testCaseWithoutSpec testCase.identifier.render
        s!"導出元 SP-{padNumber testCase.identifier.spec} が存在しない"]
    | some _ =>
      if registry.isApproved ⟨.sp, testCase.identifier.spec⟩ then []
      else
        [violation .testCaseForUnapprovedSpec testCase.identifier.render
          s!"導出元 SP-{padNumber testCase.identifier.spec} が未承認 (G2 承認前の TC 導出は禁止)"]

private def checkOrphanSpecs (registry : Registry) : List Violation :=
  registry.specs.filter
      (fun spec => registry.isApproved ⟨.sp, spec.number⟩ &&
        !registry.testCases.any (fun testCase => testCase.identifier.spec == spec.number))
    |>.map fun spec =>
      violation .orphanSpec (SimpleIdentifier.render ⟨.sp, spec.number⟩)
        "検証に紐づいていない承認済み仕様 (テストケース 0 件)"

private def checkApprovals (registry : Registry) : List Violation :=
  registry.approvals.flatMap fun record =>
    match registry.contentHashFor record.target with
    | none =>
      [violation .approvalTargetMissing record.target.render "承認対象のアーティファクトが存在しない"]
    | some currentHash =>
      if record.approval.contentHash == currentHash then []
      else
        [violation .staleApproval record.target.render
          "承認後に内容が変更されている (承認は失効。再承認が必要)"]

private def checkLearnings (registry : Registry) : List Violation :=
  let numbers := registry.learnings.map (·.number)
  let expected := List.range' 1 numbers.length
  if expected.all numbers.contains then []
  else
    [violation .learningNotContiguous "LL"
      "学び台帳は 1..N の連番でなければならない (append-only、削除禁止)"]

/-- 全検査の実行。違反ゼロ = ID の鎖が閉じている。 -/
def Registry.checkAll (registry : Registry) : List Violation :=
  checkNumbers registry ++ checkDuplicates registry ++ checkRetired registry ++
  checkValues registry ++ checkFeatureAreas registry ++ checkSpecs registry ++
  checkHypotheses registry ++ checkTestCases registry ++ checkOrphanSpecs registry ++
  checkApprovals registry ++ checkLearnings registry

def Registry.hasViolation (registry : Registry) (kind : ViolationKind) : Bool :=
  registry.checkAll.any (·.kind == kind)

end Idchain
