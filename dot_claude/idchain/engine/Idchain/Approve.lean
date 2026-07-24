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

end Idchain
