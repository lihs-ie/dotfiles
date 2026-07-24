import Lean.Data.Json
import Idchain.Registry
import Idchain.Config

/-!
# オラクル突合 (M3)

`registry.oracleQueries` × `config.oracleEngines` の全組合せを実行し、
同一クエリに対する全エンジンの出力が一致するかを機械判定する。
kind = .oracle の TC は xunit ではなくこの機構で検証される (`Idchain.Crosscheck` 参照)。
-/

namespace Idchain

/-- コマンド文字列内の `{query}` プレースホルダをクエリ文字列で置換する。 -/
def substituteQuery (command query : String) : String :=
  command.replace "{query}" query

/-- 前後の空白を除去する (`String.trim` は Slice 返却に deprecate されたため toList ベースで実装)。 -/
def trimWhitespace (s : String) : String :=
  String.ofList (((s.toList.dropWhile Char.isWhitespace).reverse.dropWhile Char.isWhitespace).reverse)

/-- 全エンジンの (trim 済) 出力が一致するか。エンジン 0/1 件は自明に一致とみなす。 -/
def judgeOracle (outputs : List (String × String)) : Bool :=
  match outputs with
  | [] => true
  | (_, first) :: rest => rest.all (fun (_, output) => output == first)

/-- 1 クエリの突合結果。outputs はエンジン名 × (trim 済) 出力。 -/
structure OracleQueryResult where
  testCase : TestCaseIdentifier
  agreed : Bool
  outputs : List (String × String)
  deriving Repr, Inhabited

/-- `oracle-results.json` に対応する全体結果。 -/
structure OracleRunResult where
  queries : List OracleQueryResult
  allAgreed : Bool
  deriving Repr, Inhabited

open Lean (Json) in
def renderOracleResultsJson (result : OracleRunResult) : String :=
  (Json.mkObj [
    ("queries", Json.arr (result.queries.map fun queryResult => Json.mkObj [
      ("testCase", Json.str queryResult.testCase.render),
      ("agreed", Json.bool queryResult.agreed),
      ("outputs", Json.arr (queryResult.outputs.map fun (engine, output) => Json.mkObj [
        ("engine", Json.str engine),
        ("output", Json.str output)]).toArray)]).toArray),
    ("allAgreed", Json.bool result.allAgreed)
  ]).pretty

open Lean (Json) in
/-- report 組込用の `oracle-results.json` 読込 (`Config.parse` の実装パターンを踏襲)。 -/
def parseOracleResultsJson (raw : String) : Except String OracleRunResult := do
  let json ← Json.parse raw
  let allAgreed ← (← json.getObjVal? "allAgreed").getBool?
  let queriesJson ← (← json.getObjVal? "queries").getArr?
  let queries ← queriesJson.toList.mapM fun queryJson => do
    let testCaseString ← (← queryJson.getObjVal? "testCase").getStr?
    let testCase ← match TestCaseIdentifier.parse testCaseString with
      | some identifier => pure identifier
      | none => throw s!"不正な TC ID: {testCaseString}"
    let agreed ← (← queryJson.getObjVal? "agreed").getBool?
    let outputsJson ← (← queryJson.getObjVal? "outputs").getArr?
    let outputs ← outputsJson.toList.mapM fun outputJson => do
      let engine ← (← outputJson.getObjVal? "engine").getStr?
      let output ← (← outputJson.getObjVal? "output").getStr?
      pure (engine, output)
    pure { testCase, agreed, outputs : OracleQueryResult }
  pure { queries, allAgreed }

end Idchain
