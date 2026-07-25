import Idchain.Registry

/-!
# 曖昧語 lint (Must-25)

決定論的な曖昧語辞書で SP 文を lint する。発見された曖昧語は check の出力に
非ブロッキングの WARNING として表示するのみで、exit code には影響しない
(違反 0 件なら lint ヒットがあっても exit 0 のまま)。
-/

namespace Idchain

private def contains (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

/-- 曖昧語 × 警告理由 (何が不明瞭になるか) の辞書。 -/
def ambiguousTermDictionary : List (String × String) := [
  ("正の値", "有限性・境界 (0 含否) が不明"),
  ("負の値", "有限性・境界 (0 含否) が不明"),
  ("適切", "判断基準が数値化されていない"),
  ("十分", "閾値が明示されていない"),
  ("高速", "具体的な数値目標がない"),
  ("速やか", "時間の基準が不明"),
  ("できるだけ", "妥協の許容範囲が不明"),
  ("原則として", "例外条件が不明"),
  ("通常は", "「通常でない」場合の扱いが不明")
]

/-- 各 SP の文をヒットした曖昧語ごとに `(SP ID, 警告文)` として返す (1 SP から複数ヒット可)。 -/
def lintSpecs (registry : Registry) : List (String × String) :=
  registry.specs.flatMap fun spec =>
    ambiguousTermDictionary.filterMap fun (term, reason) =>
      if contains spec.text term then
        some (SimpleIdentifier.render ⟨.sp, spec.number⟩, s!"曖昧語「{term}」を含む ({reason})")
      else none

end Idchain
