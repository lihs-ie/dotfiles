import Lean.Data.Json
import Idchain.Artifact
import Idchain.Oracle

/-!
# ベンチマーク判定 (M3)

`Benchmark.command` を実行して得た stdout 最終行 (整数ミリ秒) を閾値と比較し、赤黄緑を判定する。
-/

namespace Idchain

inductive BenchmarkJudgement where
  | green
  | yellow
  | red
  deriving Repr, DecidableEq, Inhabited

def BenchmarkJudgement.label : BenchmarkJudgement → String
  | .green => "green"
  | .yellow => "yellow"
  | .red => "red"

/-- 計測値 (ミリ秒) を閾値と比較して赤黄緑を判定する。green ≤ green閾値、red ≤ red閾値の間は黄。 -/
def judgeBenchmark (benchmark : Benchmark) (milliseconds : Nat) : BenchmarkJudgement :=
  if milliseconds ≤ benchmark.greenThresholdMilliseconds then .green
  else if milliseconds ≤ benchmark.redThresholdMilliseconds then .yellow
  else .red

/-- stdout の trim 後の最終行を Nat として parse する。空行・非数値は none。 -/
def parseMilliseconds (stdout : String) : Option Nat :=
  let trimmed := trimWhitespace stdout
  if trimmed.isEmpty then none
  else
    match (trimmed.splitOn "\n").getLast? with
    | none => none
    | some lastLine => (trimWhitespace lastLine).toNat?

structure BenchmarkResult where
  name : String
  milliseconds : Nat
  judgement : BenchmarkJudgement
  deriving Repr, Inhabited

structure BenchRunResult where
  benchmarks : List BenchmarkResult
  worst : BenchmarkJudgement
  deriving Repr, Inhabited

/-- 複数判定のうち最悪 (赤 > 黄 > 緑) を返す。空リストは緑扱い。 -/
def worstJudgement (judgements : List BenchmarkJudgement) : BenchmarkJudgement :=
  if judgements.contains .red then .red
  else if judgements.contains .yellow then .yellow
  else .green

open Lean (Json) in
def renderBenchResultsJson (result : BenchRunResult) : String :=
  (Json.mkObj [
    ("benchmarks", Json.arr (result.benchmarks.map fun benchmarkResult => Json.mkObj [
      ("name", Json.str benchmarkResult.name),
      ("milliseconds", Json.num ⟨(benchmarkResult.milliseconds : Int), 0⟩),
      ("judgement", Json.str benchmarkResult.judgement.label)]).toArray),
    ("worst", Json.str result.worst.label)
  ]).pretty

private def parseJudgement (s : String) : Except String BenchmarkJudgement :=
  match s with
  | "green" => .ok .green
  | "yellow" => .ok .yellow
  | "red" => .ok .red
  | other => .error s!"不正な judgement: {other}"

open Lean (Json) in
/-- report 組込用の `bench-results.json` 読込 (`Config.parse` の実装パターンを踏襲)。 -/
def parseBenchResultsJson (raw : String) : Except String BenchRunResult := do
  let json ← Json.parse raw
  let worstString ← (← json.getObjVal? "worst").getStr?
  let worst ← parseJudgement worstString
  let benchmarksJson ← (← json.getObjVal? "benchmarks").getArr?
  let benchmarks ← benchmarksJson.toList.mapM fun benchmarkJson => do
    let name ← (← benchmarkJson.getObjVal? "name").getStr?
    let milliseconds ← (← benchmarkJson.getObjVal? "milliseconds").getNat?
    let judgementString ← (← benchmarkJson.getObjVal? "judgement").getStr?
    let judgement ← parseJudgement judgementString
    pure { name, milliseconds, judgement : BenchmarkResult }
  pure { benchmarks, worst }

end Idchain
