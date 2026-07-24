import Idchain

/-! idchain fixture (正例): 発表資料の例 (SP-047 / TC-047-1/2) を再現した canon。 -/

namespace Canon

open Idchain

def problems : List Problem := [
  ⟨1, "大規模データのお客様で最頻画面の表示が遅い", [.recorded "顧客報告" "2026-06 サポート集計"]⟩
]

def values : List Value := [
  ⟨1, "最頻画面を数秒で表示できる", 1, "表示 3 秒以内"⟩
]

def featureAreas : List FeatureArea := [
  ⟨1, "集計エンジン", [1]⟩
]

def hypotheses : List Hypothesis := [
  ⟨1, "新エンジンで最頻画面の表示が約30倍速くなる", "表示時間", "3秒以内", 5, 2, [1], .untested⟩
]

def specs : List Spec := [
  ⟨47, "小計は、明細の合計と常に一致する", 1⟩
]

def testCases : List TestCase := [
  ⟨⟨47, 1⟩, "明細3件 → 小計 = 合計", .example⟩,
  ⟨⟨47, 2⟩, "明細0件 → 小計 = 0", .example⟩,
  ⟨⟨47, 3⟩, "オラクル: 小計クエリの多エンジン一致", .oracle⟩
]

def learnings : List Learning := [
  ⟨1, "2026-07-24", some 1, "初回計測は仮説を支持"⟩
]

def roadmapItems : List RoadmapItem := [
  ⟨1, "集計エンジンの汎用化", .planned, 1, some 1, "discovery"⟩
]

def retired : List SimpleIdentifier := []

-- M3: オラクル突合・ペアワイズ・ベンチマークの fixture。
def oracleQueries : List OracleQuery := [
  ⟨⟨47, 3⟩, "6"⟩
]

def factors : List Factor := [
  ⟨"データ規模", ["小", "中", "大"]⟩,
  ⟨"エンジン", ["旧", "新"]⟩
]

def benchmarks : List Benchmark := [
  ⟨"集計処理", "echo 42", 100, 1000⟩
]

/-- 状態モデル: 明細と小計。 -/
structure Model where
  lineItems : List Nat
  subtotal : Nat

def interpretations : List (SpecInterpretation Model) := [
  ⟨47, fun model => model.subtotal = model.lineItems.sum⟩
]

end Canon
