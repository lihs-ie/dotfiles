import Idchain.Pairwise
import Tests.Framework

/-! M3: ペアワイズ生成 (allPairs/generateConfigurations/coverage) のテスト。 -/

namespace Idchain.Tests.PairwiseTests

open Idchain

def twoFactors : List Factor := [
  ⟨"データ規模", ["小", "中", "大"]⟩,
  ⟨"エンジン", ["旧", "新"]⟩
]

def threeFactors : List Factor := [
  ⟨"F1", ["a1", "a2", "a3"]⟩,
  ⟨"F2", ["b1", "b2", "b3"]⟩,
  ⟨"F3", ["c1", "c2", "c3"]⟩
]

def allPairsCases : List TestResult := [
  checkEq "2 因子 (3水準×2水準) の全ペア数 = 6" (allPairs twoFactors).length 6,
  checkEq "3 因子 (3×3×3) の全ペア数 = 27 (3因子ペア×9)" (allPairs threeFactors).length 27,
  check "全ペアは重複なし" ((allPairs twoFactors).eraseDups.length == (allPairs twoFactors).length)
]

def twoFactorConfigurations := generateConfigurations twoFactors
def twoFactorCoverage := coverage twoFactors twoFactorConfigurations

def threeFactorConfigurations := generateConfigurations threeFactors
def threeFactorCoverage := coverage threeFactors threeFactorConfigurations

def generationCases : List TestResult := [
  check "2 因子: 構成数は直積 (6) 以下" (twoFactorConfigurations.length ≤ 6),
  check "2 因子: 構成数は 0 より大きい" (twoFactorConfigurations.length > 0),
  checkEq "2 因子: 網羅率 100%" twoFactorCoverage (6, 6),
  check "3 因子: 構成数は直積 (27) 未満に圧縮される" (threeFactorConfigurations.length < 27),
  check "3 因子: 構成数は 0 より大きい" (threeFactorConfigurations.length > 0),
  checkEq "3 因子: 網羅率 100%" threeFactorCoverage (27, 27),
  check "各構成は因子数と同じ長さ (2因子)" (twoFactorConfigurations.all (·.length == 2)),
  check "各構成は因子数と同じ長さ (3因子)" (threeFactorConfigurations.all (·.length == 3))
]

def oneFactorCases : List TestResult := [
  checkEq "1 因子は空を返す (スキップ相当)"
    (generateConfigurations [⟨"単独", ["x", "y"]⟩]) ([] : List (List String)),
  checkEq "因子 0 件は空を返す" (generateConfigurations []) ([] : List (List String)),
  checkEq "levels が空の因子を含むと空を返す"
    (generateConfigurations [⟨"F1", ["a"]⟩, ⟨"F2", []⟩]) ([] : List (List String))
]

/-- 決定論の検証: 同一入力を複数回実行しても同じ構成列が得られる。 -/
def determinismCases : List TestResult := [
  checkEq "決定論的 (同一入力→同一出力)"
    (generateConfigurations twoFactors) (generateConfigurations twoFactors),
  checkEq "決定論的 (3因子)"
    (generateConfigurations threeFactors) (generateConfigurations threeFactors)
]

def suite : String × List TestResult :=
  ("PairwiseTests (M3)", allPairsCases ++ generationCases ++ oneFactorCases ++ determinismCases)

end Idchain.Tests.PairwiseTests
