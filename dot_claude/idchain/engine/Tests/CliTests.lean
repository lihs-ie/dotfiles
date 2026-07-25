import Idchain.Cli
import Tests.Framework

/-! M4 (Must-22 準備): 編集ブロック hook が読む `.gate-status.json` を書き出す
    純粋コア関数 `Idchain.Cli.gateStatusJson` のテスト。フラットな 1 キー 1 行フォーマットを
    bash 側 (hook スクリプト) が grep で読むため、キー名と件数の正しさを固定する。 -/

namespace Idchain.Tests.CliTests

open Idchain
open Idchain.Cli

def approvedRecordFor (spec : Spec) : ApprovalRecord :=
  ⟨⟨.sp, spec.number⟩, approvalFor "lihs" "2026-07-24" "G2: 形式検査パス" spec⟩

def spec47 : Spec := ⟨47, "小計は、明細の合計と常に一致する", 1⟩
def spec48 : Spec := ⟨48, "未承認の仕様", 1⟩

def emptyRegistry : Registry := Registry.empty

def oneApprovedRegistry : Registry :=
  { Registry.empty with specs := [spec47], approvals := [approvedRecordFor spec47] }

def mixedRegistry : Registry :=
  { Registry.empty with specs := [spec47, spec48], approvals := [approvedRecordFor spec47] }

private def contains (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

def keyPresenceCases : List TestResult :=
  let json := gateStatusJson emptyRegistry 0
  [
    check "approvedFreshSpecs キーが含まれる" (contains json "\"approvedFreshSpecs\""),
    check "unapprovedSpecs キーが含まれる" (contains json "\"unapprovedSpecs\""),
    check "violations キーが含まれる" (contains json "\"violations\"")
  ]

def countCases : List TestResult := [
  check "SP 0 件 → approvedFreshSpecs 0 / unapprovedSpecs 0"
    (contains (gateStatusJson emptyRegistry 0) "\"approvedFreshSpecs\": 0" &&
     contains (gateStatusJson emptyRegistry 0) "\"unapprovedSpecs\": 0"),
  check "fresh 承認 1 件 → approvedFreshSpecs 1 / unapprovedSpecs 0"
    (contains (gateStatusJson oneApprovedRegistry 0) "\"approvedFreshSpecs\": 1" &&
     contains (gateStatusJson oneApprovedRegistry 0) "\"unapprovedSpecs\": 0"),
  check "承認 1 件 + 未承認 1 件 → approvedFreshSpecs 1 / unapprovedSpecs 1"
    (contains (gateStatusJson mixedRegistry 0) "\"approvedFreshSpecs\": 1" &&
     contains (gateStatusJson mixedRegistry 0) "\"unapprovedSpecs\": 1"),
  check "violationCount 引数がそのまま反映される"
    (contains (gateStatusJson mixedRegistry 5) "\"violations\": 5")
]

def suite : String × List TestResult :=
  ("CliTests (M4 gate-status)", keyPresenceCases ++ countCases)

end Idchain.Tests.CliTests
