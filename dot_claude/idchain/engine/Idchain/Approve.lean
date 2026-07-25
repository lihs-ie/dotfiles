import Idchain.Registry

/-!
# 承認書込 (U11)

`Canon/Approvals.lean` を全量再生成する codegen。手編集は禁止で、
CI は approve コマンド経由外の変更 (commit message に idchain-approve がない) を警告する。
-/

namespace Idchain

def ArtifactKind.leanConstructor : ArtifactKind → String
  | .pb => "pb"
  | .vl => "vl"
  | .fa => "fa"
  | .hy => "hy"
  | .sp => "sp"
  | .ll => "ll"
  | .rm => "rm"

/-- 同一対象の既存承認を置換して追記 (再承認)。 -/
def upsertApproval (records : List ApprovalRecord) (record : ApprovalRecord) :
    List ApprovalRecord :=
  records.filter (·.target != record.target) ++ [record]

private def renderRecord (record : ApprovalRecord) : String :=
  s!"  \{ target := ⟨Idchain.ArtifactKind.{record.target.kind.leanConstructor}, {record.target.number}⟩, approval := \{ approvedBy := {reprStr record.approval.approvedBy}, date := {reprStr record.approval.date}, note := {reprStr record.approval.note}, contentHash := 0x{renderHash record.approval.contentHash} } }"

/-- `Canon/Approvals.lean` の全文を生成する。 -/
def renderApprovalsLean (records : List ApprovalRecord) : String :=
  let body :=
    if records.isEmpty then "[]"
    else "[\n" ++ String.intercalate ",\n" (records.map renderRecord) ++ "\n]"
  s!"import Idchain

/-! idchain approve が生成するファイル。手編集禁止 (変更は lake exe idchain approve 経由 = idchain-approve)。 -/

namespace Canon

def approvals : List Idchain.ApprovalRecord := {body}

end Canon
"

/-!
## 意味一致レビュー書込 (Must-24)

`Canon/SemanticReviews.lean` を全量再生成する codegen。`renderApprovalsLean` と同じ
1 行リテラル形式・手編集禁止ヘッダを踏襲する。書込は `idchain semantic-review` コマンド経由のみ。
-/

/-- 同一 SP の既存レビューを置換して追記 (再レビュー)。 -/
def upsertSemanticReview (reviews : List SemanticReview) (review : SemanticReview) :
    List SemanticReview :=
  reviews.filter (·.spec != review.spec) ++ [review]

private def renderSemanticReview (review : SemanticReview) : String :=
  s!"  \{ spec := {review.spec}, reviewedBy := {reprStr review.reviewedBy}, date := {reprStr review.date}, verdict := {review.verdict}, findings := {reprStr review.findings}, contentHash := 0x{renderHash review.contentHash} }"

/-- `Canon/SemanticReviews.lean` の全文を生成する。 -/
def renderSemanticReviewsLean (reviews : List SemanticReview) : String :=
  let body :=
    if reviews.isEmpty then "[]"
    else "[\n" ++ String.intercalate ",\n" (reviews.map renderSemanticReview) ++ "\n]"
  s!"import Idchain

/-! idchain semantic-review が生成するファイル。手編集禁止 (変更は lake exe idchain semantic-review 経由)。 -/

namespace Canon

def semanticReviews : List Idchain.SemanticReview := {body}

end Canon
"

end Idchain
