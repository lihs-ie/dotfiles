import Idchain.Oracle
import Tests.Framework

/-! M3: オラクル突合の純粋コア (substituteQuery/judgeOracle) と JSON 入出力のテスト。 -/

namespace Idchain.Tests.OracleTests

open Idchain

def substituteCases : List TestResult := [
  checkEq "プレースホルダを置換" (substituteQuery "echo {query}" "6") "echo 6",
  checkEq "複数回出現しても全置換" (substituteQuery "{query}-{query}" "x") "x-x",
  checkEq "プレースホルダなしは不変" (substituteQuery "echo hello" "6") "echo hello"
]

def trimCases : List TestResult := [
  checkEq "前後空白除去" (trimWhitespace "  6\n") "6",
  checkEq "内部空白は保持" (trimWhitespace " a b ") "a b",
  checkEq "空文字列" (trimWhitespace "") "",
  checkEq "空白のみ" (trimWhitespace "   ") ""
]

def judgeCases : List TestResult := [
  check "全エンジン一致" (judgeOracle [("engine-a", "6"), ("engine-b", "6")]),
  check "不一致は false" (!judgeOracle [("engine-a", "6"), ("engine-b", "7")]),
  check "1 件は自明に一致" (judgeOracle [("engine-a", "6")]),
  check "0 件は自明に一致" (judgeOracle [])
]

def sampleResult : OracleRunResult := {
  queries := [
    { testCase := ⟨47, 3⟩, agreed := true, outputs := [("engine-a", "6"), ("engine-b", "6")] }
  ]
  allAgreed := true
}

def jsonRoundTripCases : List TestResult :=
  let rendered := renderOracleResultsJson sampleResult
  match parseOracleResultsJson rendered with
  | .error e => [check s!"oracle-results.json round trip parse 失敗: {e}" false]
  | .ok parsed => [
      checkEq "allAgreed 往復一致" parsed.allAgreed sampleResult.allAgreed,
      checkEq "queries 件数往復一致" parsed.queries.length sampleResult.queries.length,
      check "TC-047-3 が含まれる" ((rendered.splitOn "TC-047-3").length > 1),
      check "outputs が含まれる" ((rendered.splitOn "engine-a").length > 1)
    ]

def suite : String × List TestResult :=
  ("OracleTests (M3)", substituteCases ++ trimCases ++ judgeCases ++ jsonRoundTripCases)

end Idchain.Tests.OracleTests
