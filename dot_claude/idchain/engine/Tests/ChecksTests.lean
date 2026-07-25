import Idchain.Checks
import Idchain.Semantics
import Tests.Framework

/-! U4/U5/U6: トレーサビリティ検査・Registry・無矛盾性証明 API のテスト。 -/

namespace Idchain.Tests.ChecksTests

open Idchain

/-- G2 承認 (現内容ハッシュに束縛)。 -/
def approvedRecordFor (sp : Spec) : ApprovalRecord :=
  ⟨⟨.sp, sp.number⟩, approvalFor "lihs" "2026-07-24" "G2: 形式検査パス" sp⟩

def spec47 : Spec := ⟨47, "小計は、明細の合計と常に一致する", 1⟩

/-- 発表資料の例 (`SP-047` / `TC-047-1/2`) を模した正例 Registry。 -/
def validRegistry : Registry := {
  problems := [⟨1, "大規模データで最頻画面の表示が遅い", [.recorded "顧客報告" "2026-06 サポート集計"]⟩],
  values := [⟨1, "最頻画面を数秒で表示できる", 1, "表示 3 秒以内"⟩],
  featureAreas := [⟨1, "集計エンジン", [1]⟩],
  hypotheses := [⟨1, "新エンジンで表示が約30倍速くなる", "表示時間", "3秒以内", 5, 2, [1], .untested⟩],
  specs := [spec47],
  testCases := [
    ⟨⟨47, 1⟩, "明細3件 → 小計 = 合計", .example⟩,
    ⟨⟨47, 2⟩, "明細0件 → 小計 = 0", .example⟩],
  learnings := [⟨1, "2026-07-24", some 1, "初回計測は仮説を支持"⟩],
  approvals := [approvedRecordFor spec47],
  retired := [],
  semanticReviews := [⟨47, "lihs", "2026-07-24", true, "多義語なし・境界値明示済み・invariant と一致", contentHashOf spec47⟩]
}

def positiveCases : List TestResult := [
  checkEq "正例 Registry は違反 0 件" validRegistry.checkAll.length 0,
  check "SP-047 は fresh 承認済" (validRegistry.isApproved ⟨.sp, 47⟩),
  check "未承認 PB-001 は isApproved false" (!validRegistry.isApproved ⟨.pb, 1⟩)
]

def has (registry : Registry) (kind : ViolationKind) : Bool :=
  registry.hasViolation kind

def negativeCases : List TestResult := [
  check "PB 番号重複 → duplicate-identifier"
    (has { validRegistry with
      problems := validRegistry.problems ++ [⟨1, "別の課題", []⟩] } .duplicateIdentifier),
  check "TC (47,1) 重複 → duplicate-test-case"
    (has { validRegistry with
      testCases := validRegistry.testCases ++ [⟨⟨47, 1⟩, "重複", .example⟩] } .duplicateTestCase),
  check "退役 SP-047 の再利用 → retired-identifier-reuse"
    (has { validRegistry with retired := [⟨.sp, 47⟩] } .retiredIdentifierReuse),
  check "VL の対応 PB 不在 → value-without-problem"
    (has { validRegistry with values := [⟨1, "v", 99, "c"⟩] } .valueWithoutProblem),
  check "FA の参照 VL 不在 → feature-area-without-value"
    (has { validRegistry with featureAreas := [⟨1, "fa", [99]⟩] } .featureAreaWithoutValue),
  check "FA の VL 参照が空 → feature-area-without-value"
    (has { validRegistry with featureAreas := [⟨1, "fa", []⟩] } .featureAreaWithoutValue),
  check "SP の帰属 FA 不在 → spec-without-feature-area"
    (has { validRegistry with featureAreas := [], values := [], hypotheses := [], learnings := [] }
      .specWithoutFeatureArea),
  check "HY の PB 参照が空 → hypothesis-without-anchor"
    (has { validRegistry with hypotheses := [⟨1, "h", "m", "t", 5, 2, [], .untested⟩] }
      .hypothesisWithoutAnchor),
  check "HY の参照 PB 不在 → hypothesis-without-anchor"
    (has { validRegistry with hypotheses := [⟨1, "h", "m", "t", 5, 2, [99], .untested⟩] }
      .hypothesisWithoutAnchor),
  check "TC の親 SP 不在 → test-case-without-spec"
    (has { validRegistry with
      testCases := validRegistry.testCases ++ [⟨⟨99, 1⟩, "親なし", .example⟩] } .testCaseWithoutSpec),
  check "未承認 SP への TC → test-case-for-unapproved-spec"
    (has { validRegistry with
      specs := validRegistry.specs ++ [⟨48, "未承認仕様", 1⟩],
      testCases := validRegistry.testCases ++ [⟨⟨48, 1⟩, "早すぎる導出", .example⟩] }
      .testCaseForUnapprovedSpec),
  check "承認済 SP に TC 0 件 → orphan-spec"
    (let spec48 : Spec := ⟨48, "承認済だがテスト未導出", 1⟩
     has { validRegistry with
      specs := validRegistry.specs ++ [spec48],
      approvals := validRegistry.approvals ++ [approvedRecordFor spec48] } .orphanSpec),
  check "未承認 SP に TC 0 件は違反ではない (G2 前のパイプライン)"
    (!(has { validRegistry with specs := validRegistry.specs ++ [⟨48, "起草中", 1⟩] } .orphanSpec)),
  check "承認後の内容変更 → stale-approval"
    (has { validRegistry with specs := [{ spec47 with text := "改変された仕様文" }] } .staleApproval),
  check "承認対象の不在 → approval-target-missing"
    (has { validRegistry with
      approvals := validRegistry.approvals ++
        [⟨⟨.sp, 99⟩, approvalFor "lihs" "2026-07-24" "対象なし" spec47⟩] } .approvalTargetMissing),
  check "LL 欠番 (1,3) → learning-not-contiguous"
    (has { validRegistry with
      learnings := [⟨1, "2026-07-24", none, "a"⟩, ⟨3, "2026-07-24", none, "b"⟩] }
      .learningNotContiguous),
  check "PB 番号 0 → invalid-number"
    (has { validRegistry with problems := validRegistry.problems ++ [⟨0, "zero", []⟩] } .invalidNumber),
  check "TC 枝番 0 → invalid-number"
    (has { validRegistry with
      testCases := validRegistry.testCases ++ [⟨⟨47, 0⟩, "枝番0", .example⟩] } .invalidNumber)
]

-- M5 (Must-24/29): RM・意味一致レビューのトレーサビリティ検査
def approvedRoadmapRecordFor (item : RoadmapItem) : ApprovalRecord :=
  ⟨⟨.rm, item.number⟩, approvalFor "lihs" "2026-07-24" "inCycle 化承認" item⟩

def roadmapNegativeCases : List TestResult := [
  check "RM.hypothesis に存在しない HY → roadmap-hypothesis-missing"
    (has { validRegistry with
      roadmapItems := [⟨1, "軽量化", .planned, 1, some 99, "discovery"⟩] } .roadmapHypothesisMissing),
  check "RM.hypothesis が既存 HY を指せば違反ではない"
    (!(has { validRegistry with
      roadmapItems := [⟨1, "軽量化", .planned, 1, some 1, "discovery"⟩] } .roadmapHypothesisMissing)),
  check "RM 番号欠番 (1,3) → roadmap-not-contiguous"
    (has { validRegistry with
      roadmapItems := [⟨1, "a", .planned, 1, none, "discovery"⟩, ⟨3, "b", .planned, 2, none, "discovery"⟩] }
      .roadmapNotContiguous),
  check "RM 番号連番 (1,2) は違反ではない"
    (!(has { validRegistry with
      roadmapItems := [⟨1, "a", .planned, 1, none, "discovery"⟩, ⟨2, "b", .planned, 2, none, "discovery"⟩] }
      .roadmapNotContiguous)),
  check "inCycle RM が未承認 → in-cycle-roadmap-unapproved"
    (has { validRegistry with
      roadmapItems := [⟨1, "着手中の項目", .inCycle, 1, none, "discovery"⟩] } .inCycleRoadmapUnapproved),
  check "inCycle RM が fresh 承認済なら違反ではない"
    (!(let item : RoadmapItem := ⟨1, "着手中の項目", .inCycle, 1, none, "discovery"⟩
       has { validRegistry with
        roadmapItems := [item], approvals := validRegistry.approvals ++ [approvedRoadmapRecordFor item] }
        .inCycleRoadmapUnapproved)),
  check "planned RM は未承認でも違反ではない (inCycle のみ承認必須)"
    (!(has { validRegistry with
      roadmapItems := [⟨1, "計画中の項目", .planned, 1, none, "discovery"⟩] } .inCycleRoadmapUnapproved)),
  check "dropped も削除禁止 (RM は連番の一員として残る)"
    (!(has { validRegistry with
      roadmapItems := [⟨1, "見送り", .dropped, 1, none, "discovery"⟩] } .roadmapNotContiguous))
]

def semanticReviewNegativeCases : List TestResult := [
  check "承認済 SP-047 に review なし → semantic-review-missing"
    (has { validRegistry with semanticReviews := [] } .semanticReviewMissing),
  check "review はあるが verdict=false → semantic-review-missing のまま"
    (has { validRegistry with
      semanticReviews := [⟨47, "lihs", "2026-07-24", false, "多義語あり", contentHashOf spec47⟩] }
      .semanticReviewMissing),
  check "review の contentHash が現内容と不一致 → semantic-review-stale"
    (has { validRegistry with
      semanticReviews := [⟨47, "lihs", "2026-07-24", true, "古いレビュー", 0x1⟩] } .semanticReviewStale),
  checkEq "起草中 SP (未承認) は semantic-review-missing の対象にならない (0 件のまま)"
    (({ validRegistry with specs := validRegistry.specs ++ [⟨48, "起草中", 1⟩] } : Registry).checkAll.filter
      (·.kind == .semanticReviewMissing)).length 0,
  check "fresh な review (verdict=true・hash一致) があれば違反ではない"
    (!(has validRegistry .semanticReviewMissing) && !(has validRegistry .semanticReviewStale))
]

-- U6: 無矛盾性証明 API のコンパイル時実証
-- 発表の例: 「小計は、明細の合計と常に一致する」を持つモデルで witness を構成する。
structure LedgerModel where
  lineItems : List Nat
  subtotal : Nat

def interpretations : List (SpecInterpretation LedgerModel) := [
  ⟨47, fun model => model.subtotal = model.lineItems.sum⟩
]

/-- witness = 明細 [1,2,3]・小計 6。証明が閉じること自体が U6 の検証。 -/
def consistencyExample : ConsistencyProof LedgerModel validRegistry interpretations := {
  witness := ⟨[1, 2, 3], 6⟩
  sound := by
    intro interpretation mem
    simp only [interpretations, List.mem_singleton] at mem
    subst mem
    rfl
  complete := by decide
}

def semanticsCases : List TestResult := [
  check "ConsistencyProof の witness が構成できている"
    (consistencyExample.witness.subtotal == 6)
]

def suite : String × List TestResult :=
  ("ChecksTests (U4/U5/U6/M5)",
    positiveCases ++ negativeCases ++ semanticsCases ++
    roadmapNegativeCases ++ semanticReviewNegativeCases)

end Idchain.Tests.ChecksTests
