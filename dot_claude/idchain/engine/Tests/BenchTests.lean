import Idchain.Bench
import Tests.Framework

/-! M3: ベンチマーク判定 (judgeBenchmark/parseMilliseconds) と JSON 入出力のテスト。 -/

namespace Idchain.Tests.BenchTests

open Idchain

def sampleBenchmark : Benchmark := ⟨"サンプル", "echo 42", 100, 1000⟩

def judgeBenchmarkCases : List TestResult := [
  checkEq "green 閾値ちょうど → green" (judgeBenchmark sampleBenchmark 100) .green,
  checkEq "green 閾値+1 → yellow" (judgeBenchmark sampleBenchmark 101) .yellow,
  checkEq "red 閾値ちょうど → yellow" (judgeBenchmark sampleBenchmark 1000) .yellow,
  checkEq "red 閾値+1 → red" (judgeBenchmark sampleBenchmark 1001) .red,
  checkEq "0ms → green" (judgeBenchmark sampleBenchmark 0) .green
]

def parseMillisecondsCases : List TestResult := [
  checkEq "正常な単一行" (parseMilliseconds "42") (some 42),
  checkEq "前後空白付き" (parseMilliseconds "  42  \n") (some 42),
  checkEq "複数行は最終行を採用" (parseMilliseconds "warming up\ndone\n42") (some 42),
  checkEq "非数値は none" (parseMilliseconds "not a number") (none : Option Nat),
  checkEq "空文字列は none" (parseMilliseconds "") (none : Option Nat),
  checkEq "空白のみは none" (parseMilliseconds "   \n  ") (none : Option Nat)
]

def worstJudgementCases : List TestResult := [
  checkEq "空リストは green" (worstJudgement []) .green,
  checkEq "green と yellow の最悪は yellow" (worstJudgement [.green, .yellow]) .yellow,
  checkEq "yellow と red の最悪は red" (worstJudgement [.yellow, .red]) .red,
  checkEq "全 green は green" (worstJudgement [.green, .green]) .green
]

def sampleRunResult : BenchRunResult := {
  benchmarks := [⟨"サンプル", 42, .green⟩]
  worst := .green
}

def jsonRoundTripCases : List TestResult :=
  let rendered := renderBenchResultsJson sampleRunResult
  match parseBenchResultsJson rendered with
  | .error e => [check s!"bench-results.json round trip parse 失敗: {e}" false]
  | .ok parsed => [
      checkEq "worst 往復一致" parsed.worst sampleRunResult.worst,
      checkEq "benchmarks 件数往復一致" parsed.benchmarks.length sampleRunResult.benchmarks.length,
      check "milliseconds が含まれる" ((rendered.splitOn "42").length > 1),
      check "judgement 文字列が含まれる" ((rendered.splitOn "green").length > 1)
    ]

def suite : String × List TestResult :=
  ("BenchTests (M3)", judgeBenchmarkCases ++ parseMillisecondsCases ++ worstJudgementCases ++ jsonRoundTripCases)

end Idchain.Tests.BenchTests
