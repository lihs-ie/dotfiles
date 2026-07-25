import Idchain.Artifact

/-!
# ペアワイズ生成 (M3)

因子 (Factor) の全 2 因子組合せ (ペア) を貪欲法で被覆する構成一覧を生成する。
直積 (全構成) より少ない構成数で「全 2 因子ペアが最低 1 構成に現れる」を満たすのが目的。
-/

namespace Idchain

/-- 因子 index × 水準の全 2 因子ペア (i < j)。 -/
def allPairs (factors : List Factor) : List ((Nat × String) × (Nat × String)) :=
  let indexedFactors := (List.range factors.length).zip factors
  indexedFactors.flatMap fun (i, factorI) =>
    indexedFactors.flatMap fun (j, factorJ) =>
      if i < j then
        factorI.levels.flatMap fun levelI =>
          factorJ.levels.map fun levelJ => ((i, levelI), (j, levelJ))
      else []

/-- ある構成 (因子 index 順の水準リスト) が被覆する全 2 因子ペア。 -/
private def pairsOfConfiguration (configuration : List String) :
    List ((Nat × String) × (Nat × String)) :=
  let indexed := (List.range configuration.length).zip configuration
  indexed.flatMap fun (i, levelI) =>
    indexed.flatMap fun (j, levelJ) =>
      if i < j then [((i, levelI), (j, levelJ))] else []

/-- 因子 index の水準の中で、`remaining` に最も多く出現する水準 (同点は先頭優先)。 -/
private def bestLevel (remaining : List ((Nat × String) × (Nat × String)))
    (index : Nat) (levels : List String) : String :=
  let score (level : String) : Nat :=
    (remaining.filter fun pair => pair.1 == (index, level) || pair.2 == (index, level)).length
  match levels with
  | [] => ""
  | first :: rest =>
    (rest.foldl (fun best level => if score level > score best then level else best) first)

/-- 1 反復分の構成を貪欲法で構築する。remaining の先頭ペアをアンカーとして必ず被覆し、
残りの因子は「現時点の remaining に最も多く出現する水準」を選ぶ (決定論的、同点は先頭優先)。 -/
private def buildOneConfiguration (indexedFactors : List (Nat × Factor))
    (remaining : List ((Nat × String) × (Nat × String)))
    (anchor : (Nat × String) × (Nat × String)) : List String :=
  let ((anchorIndexA, anchorLevelA), (anchorIndexB, anchorLevelB)) := anchor
  indexedFactors.map fun (index, factor) =>
    if index == anchorIndexA then anchorLevelA
    else if index == anchorIndexB then anchorLevelB
    else bestLevel remaining index factor.levels

/-- アンカーペアを必ず消費するため `remaining` は反復毎に真に減少し、有限回で停止する。 -/
private partial def loop (indexedFactors : List (Nat × Factor))
    (remaining : List ((Nat × String) × (Nat × String)))
    (acc : List (List String)) : List (List String) :=
  match remaining with
  | [] => acc
  | anchor :: _ =>
    let configuration := buildOneConfiguration indexedFactors remaining anchor
    let covered := (pairsOfConfiguration configuration).filter (remaining.contains ·)
    let remaining' := remaining.filter (fun pair => !(covered.contains pair))
    loop indexedFactors remaining' (acc ++ [configuration])

/-- 貪欲法によるペアワイズ構成生成。因子 < 2 または levels が空の因子があれば空を返す。 -/
def generateConfigurations (factors : List Factor) : List (List String) :=
  if factors.length < 2 || factors.any (·.levels.isEmpty) then []
  else
    let indexedFactors := (List.range factors.length).zip factors
    loop indexedFactors (allPairs factors) []

/-- 被覆済ペア数 × 全ペア数。 -/
def coverage (factors : List Factor) (configurations : List (List String)) : Nat × Nat :=
  let allPairsList := allPairs factors
  let coveredPairs := (configurations.flatMap pairsOfConfiguration).eraseDups
  ((allPairsList.filter (coveredPairs.contains ·)).length, allPairsList.length)

end Idchain
