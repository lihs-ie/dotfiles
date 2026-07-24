import Idchain

/-! idchain approve が生成するファイル。手編集禁止 (変更は lake exe idchain approve 経由 = idchain-approve)。 -/

namespace Canon

def approvals : List Idchain.ApprovalRecord := [
  { target := ⟨Idchain.ArtifactKind.sp, 47⟩, approval := { approvedBy := "lihs", date := "2026-07-24", note := "負例: 承認済だが TC ゼロ", contentHash := 0x2395117aa33d5591 } },
  { target := ⟨Idchain.ArtifactKind.pb, 1⟩, approval := { approvedBy := "lihs", date := "2026-07-24", note := "負例: ハッシュ失効", contentHash := 0x1 } }
]

end Canon
