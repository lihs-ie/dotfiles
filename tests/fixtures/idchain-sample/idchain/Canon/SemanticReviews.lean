import Idchain

/-! idchain semantic-review が生成するファイル。手編集禁止 (変更は lake exe idchain semantic-review 経由)。 -/

namespace Canon

def semanticReviews : List Idchain.SemanticReview := [
  { spec := 47, reviewedBy := "reviewer-agent", date := "2026-07-25", verdict := true, findings := "多義語なし・境界値明示済み・invariant と一致", contentHash := 0xed23ff91bfa1d939 }
]

end Canon
