import Idchain.Views
import Idchain.Report
import Idchain.Approve
import Idchain.Config
import Idchain.Oracle
import Idchain.Bench
import Tests.ChecksTests
import Tests.Framework

/-! U9/U10/U11: ビュー生成・検証レポート・承認 codegen のテスト。 -/

namespace Idchain.Tests.GenerationTests

open Idchain
open Idchain.Tests.ChecksTests (validRegistry spec47)

def contains (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

def viewCommonCases : List TestResult :=
  (views validRegistry).map fun (name, content) =>
    check s!"{name} は DO NOT EDIT ヘッダで始まる" (content.startsWith viewHeader)

def whyWhat := renderWhyWhat validRegistry
def specification := renderSpecification validRegistry
def testDesign := renderTestDesign validRegistry
def ledger := renderLedger validRegistry

def whyWhatCases : List TestResult := [
  check "PB-001 と課題文" (contains whyWhat "PB-001" && contains whyWhat "大規模データで最頻画面の表示が遅い"),
  check "VL-001 と合格ライン" (contains whyWhat "VL-001" && contains whyWhat "表示 3 秒以内"),
  check "FA-001" (contains whyWhat "FA-001"),
  check "HY-001 と閾値" (contains whyWhat "HY-001" && contains whyWhat "3秒以内"),
  check "要証拠の出典が表示される" (contains whyWhat "2026-06 サポート集計"),
  check "Traceability 連鎖" (contains whyWhat "PB-001 ⇔ VL-001 ⇔ FA-001")
]

def specificationCases : List TestResult := [
  check "SP-047 と仕様文" (contains specification "SP-047" && contains specification "小計は、明細の合計と常に一致する"),
  check "承認状態 (承認済)" (contains specification "承認済 (lihs, 2026-07-24)"),
  check "意思の痕跡 (note)" (contains specification "G2: 形式検査パス"),
  check "FA 見出しの下に SP が並ぶ" (contains specification "FA-001"),
  check "導出テストの一覧" (contains specification "TC-047-1")
]

def testDesignCases : List TestResult := [
  check "SP 見出し" (contains testDesign "SP-047"),
  check "TC-047-1 と説明" (contains testDesign "TC-047-1" && contains testDesign "明細3件 → 小計 = 合計"),
  check "TC-047-2" (contains testDesign "TC-047-2"),
  check "kind 表示" (contains testDesign "example")
]

def ledgerCases : List TestResult := [
  check "LL-001" (contains ledger "LL-001"),
  check "関連仮説 HY-001" (contains ledger "HY-001"),
  check "学びの本文" (contains ledger "初回計測は仮説を支持")
]

-- M5 (Must-29): roadmap.md ビュー
def registryWithRoadmap : Registry :=
  { validRegistry with
    roadmapItems := [
      ⟨2, "第二弾: バッチ処理最適化", .planned, 2, none, "discovery"⟩,
      ⟨1, "第一弾: 集計エンジン刷新", .inCycle, 1, some 1, "discovery"⟩
    ] }

def roadmap := renderRoadmap registryWithRoadmap

def roadmapCases : List TestResult := [
  check "DO NOT EDIT ヘッダで始まる" (roadmap.startsWith viewHeader),
  check "RM-001 と RM-002 が含まれる" (contains roadmap "RM-001" && contains roadmap "RM-002"),
  check "題名が含まれる" (contains roadmap "第一弾: 集計エンジン刷新"),
  check "関連 HY-001 が含まれる" (contains roadmap "HY-001"),
  check "hypothesis なしは — 表示" (contains roadmap "—"),
  check "出典 discovery が含まれる" (contains roadmap "discovery"),
  check "優先度昇順: RM-001 (priority 1) が RM-002 (priority 2) より先に出現"
    (((roadmap.splitOn "RM-001").headD "").length < ((roadmap.splitOn "RM-002").headD "").length)
]

-- U10: レポート
def passResult : CrosscheckResult :=
  { orphanTests := [], unknownReferences := [], unimplementedTestCases := [],
    unexecutedTestCases := [], failedTestCases := [],
    passedTestCases := [⟨47, 1⟩, ⟨47, 2⟩] }

def failResult : CrosscheckResult :=
  { passResult with failedTestCases := [⟨47, 2⟩], passedTestCases := [⟨47, 1⟩] }

def verdictCases : List TestResult :=
  let verdictsPass := specVerdicts validRegistry passResult
  let verdictsFail := specVerdicts validRegistry failResult
  [
    checkEq "SP は 1 件" verdictsPass.length 1,
    check "全 TC pass で verdict passed" (verdictsPass.all (·.passed)),
    check "全 TC pass で verified" (verdictsPass.all (·.verified)),
    check "TC 失敗で verdict not passed" (!(verdictsFail.all (·.passed))),
    checkEq "unchained 0 件 (承認済 + 実行済)" (unchainedSpecCount verdictsPass) 0,
    check "overallPass 成立" (overallPass [] passResult verdictsPass),
    check "失敗 TC ありで overallPass 不成立" (!(overallPass [] failResult verdictsFail)),
    check "違反ありで overallPass 不成立"
      (!(overallPass [⟨.orphanSpec, "SP-047", ""⟩] passResult verdictsPass))
  ]

-- M3: SP に oracle kind の TC が追加されても crosscheck ベースの合否判定に影響しない
def registryWithOracleTestCase : Registry := {
  validRegistry with
  testCases := validRegistry.testCases ++ [⟨⟨47, 3⟩, "オラクル: 小計クエリの多エンジン一致", .oracle⟩]
}

def verdictWithOracleCases : List TestResult :=
  let verdicts := specVerdicts registryWithOracleTestCase passResult
  [
    checkEq "SP は 1 件 (oracle TC 追加後も)" verdicts.length 1,
    check "oracle TC を含んでも xunit 全 pass なら verdict passed" (verdicts.all (·.passed)),
    check "verdict の testCases には oracle TC も表示上含まれる"
      ((verdicts.head!.testCases.contains (⟨47, 3⟩ : TestCaseIdentifier)))
  ]

def reportMarkdown := renderReportMarkdown "2026-07-24" validRegistry [] passResult

def reportCases : List TestResult := [
  check "日付" (contains reportMarkdown "2026-07-24"),
  check "総合判定 PASS" (contains reportMarkdown "PASS"),
  check "検証に紐づいていない仕様: 0 件" (contains reportMarkdown "検証に紐づいていない仕様: 0 件"),
  check "仕様に紐づいていないテスト: 0 件" (contains reportMarkdown "仕様に紐づいていないテスト: 0 件"),
  check "SP-047 の行" (contains reportMarkdown "SP-047"),
  check "JSON に overall" (contains (renderReportJson "2026-07-24" validRegistry [] passResult) "overall"),
  check "失敗時は FAIL 表示"
    (contains (renderReportMarkdown "2026-07-24" validRegistry [] failResult) "FAIL")
]

-- M3: report への oracle/bench 組込
def oracleAgreed : OracleRunResult :=
  { queries := [{ testCase := ⟨47, 3⟩, agreed := true, outputs := [("a", "6"), ("b", "6")] }]
    allAgreed := true }

def oracleDisagreed : OracleRunResult :=
  { queries := [{ testCase := ⟨47, 3⟩, agreed := false, outputs := [("a", "6"), ("b", "7")] }]
    allAgreed := false }

def benchGreen : BenchRunResult :=
  { benchmarks := [⟨"サンプル", 42, .green⟩], worst := .green }

def benchRed : BenchRunResult :=
  { benchmarks := [⟨"サンプル", 5000, .red⟩], worst := .red }

def reportOracleBenchCases : List TestResult := [
  check "oracle/bench 未実施は「未実施」と表示"
    (let md := renderReportMarkdown "2026-07-24" validRegistry [] passResult none none
     contains md "## オラクル突合" && contains md "## ベンチマーク" && contains md "未実施"),
  check "oracle 未実施は overallPass に影響しない"
    (overallPass [] passResult (specVerdicts validRegistry passResult) none none),
  check "oracle 一致は overallPass 成立を維持"
    (overallPass [] passResult (specVerdicts validRegistry passResult) (some oracleAgreed) none),
  check "oracle 不一致は overallPass を FAIL にする"
    (!(overallPass [] passResult (specVerdicts validRegistry passResult) (some oracleDisagreed) none)),
  check "bench green は overallPass 成立を維持"
    (overallPass [] passResult (specVerdicts validRegistry passResult) none (some benchGreen)),
  check "bench red は overallPass を FAIL にする"
    (!(overallPass [] passResult (specVerdicts validRegistry passResult) none (some benchRed))),
  check "レポート md にオラクル結果が含まれる"
    (contains (renderReportMarkdown "2026-07-24" validRegistry [] passResult (some oracleAgreed) none)
      "TC-047-3"),
  check "レポート md にベンチマーク結果が含まれる"
    (contains (renderReportMarkdown "2026-07-24" validRegistry [] passResult none (some benchGreen))
      "サンプル"),
  check "レポート json に oracle/bench キーが含まれる"
    (let json := renderReportJson "2026-07-24" validRegistry [] passResult (some oracleAgreed) (some benchGreen)
     contains json "\"oracle\"" && contains json "\"bench\"")
]

-- Must-28: RM 反映強制 (unreflectedBenchmarks + overallPass への組込)
def benchYellow : BenchRunResult :=
  { benchmarks := [⟨"重い処理", 500, .yellow⟩], worst := .yellow }

def registryWithBenchRoadmap : Registry :=
  { Registry.empty with roadmapItems := [⟨1, "改善", .planned, 1, none, "bench:重い処理"⟩] }

def registryWithDroppedBenchRoadmap : Registry :=
  { Registry.empty with roadmapItems := [⟨1, "見送り", .dropped, 1, none, "bench:重い処理"⟩] }

def unreflectedBenchmarkCases : List TestResult := [
  checkEq "yellow で対応 RM なし → 検出" (unreflectedBenchmarks Registry.empty benchYellow) ["重い処理"],
  checkEq "yellow で対応 RM あり (source一致・非dropped) → 空"
    (unreflectedBenchmarks registryWithBenchRoadmap benchYellow) [],
  checkEq "green は RM なくても空" (unreflectedBenchmarks Registry.empty benchGreen) [],
  checkEq "dropped RM のみ → 検出"
    (unreflectedBenchmarks registryWithDroppedBenchRoadmap benchYellow) ["重い処理"]
]

def reportRoadmapReflectionCases : List TestResult := [
  check "yellow bench + 対応 RM で overallPass 維持"
    (overallPass [] passResult (specVerdicts validRegistry passResult) none (some benchYellow)
      registryWithBenchRoadmap),
  check "yellow bench + RM なしで overallPass FAIL"
    (!(overallPass [] passResult (specVerdicts validRegistry passResult) none (some benchYellow)
      validRegistry)),
  check "未反映ベンチは report md に「未反映」が明記される"
    (contains
      (renderReportMarkdown "2026-07-24" validRegistry [] passResult none (some benchYellow))
      "未反映"),
  check "対応 RM があれば report md に「未反映」は出ない"
    (!(contains
      (renderReportMarkdown "2026-07-24" registryWithBenchRoadmap [] passResult none (some benchYellow))
      "未反映"))
]

-- U11: 承認 codegen
def sampleRecord : ApprovalRecord :=
  ⟨⟨.sp, 47⟩, approvalFor "lihs" "2026-07-24" "G2: \"形式検査\" パス" spec47⟩

def approvalsLean := renderApprovalsLean [sampleRecord]

def approveCases : List TestResult := [
  check "namespace Canon" (contains approvalsLean "namespace Canon"),
  check "target 構築子" (contains approvalsLean "ArtifactKind.sp"),
  check "番号 47" (contains approvalsLean "47"),
  check "ハッシュ 16 進リテラル"
    (contains approvalsLean s!"0x{renderHash sampleRecord.approval.contentHash}"),
  check "note が Lean 文字列としてエスケープされる" (contains approvalsLean "\\\"形式検査\\\""),
  check "手編集禁止の注記" (contains approvalsLean "手編集禁止"),
  check "空リストも整形" (contains (renderApprovalsLean []) "[]"),
  checkEq "upsert は同一対象を置換"
    ((upsertApproval [sampleRecord]
      ⟨⟨.sp, 47⟩, approvalFor "lihs" "2026-07-25" "再承認" spec47⟩).length) 1,
  checkEq "upsert は別対象を追加"
    ((upsertApproval [sampleRecord]
      ⟨⟨.pb, 1⟩, approvalFor "lihs" "2026-07-25" "G1" spec47⟩).length) 2
]

-- Must-24: 意味一致レビュー codegen
def sampleReview : SemanticReview :=
  ⟨47, "lihs", "2026-07-24", true, "多義語なし・\"境界値\"明示済み", contentHashOf spec47⟩

def semanticReviewsLean := renderSemanticReviewsLean [sampleReview]

def semanticReviewCases : List TestResult := [
  check "namespace Canon" (contains semanticReviewsLean "namespace Canon"),
  check "spec 番号 47" (contains semanticReviewsLean "spec := 47"),
  check "verdict true" (contains semanticReviewsLean "verdict := true"),
  check "findings がエスケープされる" (contains semanticReviewsLean "\\\"境界値\\\""),
  check "ハッシュ 16 進リテラル"
    (contains semanticReviewsLean s!"0x{renderHash sampleReview.contentHash}"),
  check "手編集禁止の注記" (contains semanticReviewsLean "手編集禁止"),
  check "空リストも整形" (contains (renderSemanticReviewsLean []) "[]"),
  checkEq "upsert は同一 spec を置換"
    ((upsertSemanticReview [sampleReview]
      ⟨47, "lihs", "2026-07-25", true, "再レビュー", contentHashOf spec47⟩).length) 1,
  checkEq "upsert は別 spec を追加"
    ((upsertSemanticReview [sampleReview]
      ⟨48, "lihs", "2026-07-25", true, "別仕様", 0⟩).length) 2
]

def configNullCases : List TestResult :=
  match Config.parse "{\"xunitPath\": null, \"testFileRoots\": null}" with
  | .error e => [check s!"null 耐性 parse 失敗: {e}" false]
  | .ok config => [
      checkEq "null xunitPath は none" config.xunitPath (none : Option String),
      checkEq "null 配列は空" config.testFileRoots ([] : List String)
    ]

def suite : String × List TestResult :=
  ("GenerationTests (U9/U10/U11/M5)",
    viewCommonCases ++ whyWhatCases ++ specificationCases ++ testDesignCases ++ ledgerCases ++
    roadmapCases ++
    verdictCases ++ verdictWithOracleCases ++ reportCases ++ reportOracleBenchCases ++
    unreflectedBenchmarkCases ++ reportRoadmapReflectionCases ++
    approveCases ++ semanticReviewCases ++ configNullCases)

end Idchain.Tests.GenerationTests
