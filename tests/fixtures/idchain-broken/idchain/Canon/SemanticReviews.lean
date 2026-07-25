import Idchain

/-! idchain semantic-review が生成するファイル。手編集禁止 (変更は lake exe idchain semantic-review 経由)。 -/

namespace Canon

-- M5 負例: SP-048 のレビューだが contentHash が現内容と一致しない (semantic-review-stale の負例)。
-- 手書き追加 (CLI を経由していない = 意図的な負例)。
def semanticReviews : List Idchain.SemanticReview := [
  { spec := 48, reviewedBy := "lihs", date := "2026-07-25", verdict := true, findings := "負例: SP 文変更後に再レビューされていない", contentHash := 0x1 }
]

end Canon
