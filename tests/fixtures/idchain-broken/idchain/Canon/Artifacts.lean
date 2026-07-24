import Idchain

/-! idchain fixture (負例): 意図的に 5 種のトレーサビリティ違反を仕込んだ canon。 -/

namespace Canon

open Idchain

def problems : List Problem := [
  ⟨1, "課題文", []⟩
]

def values : List Value := [
  ⟨1, "価値文", 1, "合格ライン"⟩
]

def featureAreas : List FeatureArea := [
  ⟨1, "領域名", [1]⟩
]

def hypotheses : List Hypothesis := []

def specs : List Spec := [
  ⟨47, "承認済だが TC ゼロの仕様", 1⟩,
  ⟨48, "未承認の仕様", 1⟩
]

def testCases : List TestCase := [
  ⟨⟨48, 1⟩, "未承認 SP への TC", .example⟩
]

def learnings : List Learning := [
  ⟨1, "2026-07-24", none, "初回計測は仮説を支持"⟩,
  ⟨3, "2026-07-24", none, "LL-002 が欠番 (append-only 違反の負例)"⟩
]

def retired : List SimpleIdentifier := [⟨.fa, 1⟩]

/-- 状態モデル: 負例のためプレースホルダのみ。 -/
structure Model where
  placeholder : Unit := ()

def interpretations : List (SpecInterpretation Model) := [
  ⟨47, fun _ => True⟩,
  ⟨48, fun _ => True⟩
]

end Canon
