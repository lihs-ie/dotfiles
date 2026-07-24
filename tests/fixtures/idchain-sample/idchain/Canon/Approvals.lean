import Idchain

/-! idchain approve が生成するファイル。手編集禁止 (変更は lake exe idchain approve 経由 = idchain-approve)。 -/

namespace Canon

def approvals : List Idchain.ApprovalRecord := [
  { target := ⟨Idchain.ArtifactKind.sp, 47⟩, approval := { approvedBy := "lihs", date := "2026-07-24", note := "G2: 形式検査パス・発表資料の例を採用", contentHash := 0xed23ff91bfa1d939 } }
]

end Canon
