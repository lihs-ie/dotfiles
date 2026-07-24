import Idchain.Config
import Idchain.Export
import Idchain.Crosscheck
import Tests.Framework

/-! U7/U8: export JSON・config parse・TC⇄テスト突合のテスト。 -/

namespace Idchain.Tests.CrosscheckTests

open Idchain

def configJson : String := "{
  \"repoRoot\": \"..\",
  \"testFileRoots\": [\"Tests\"],
  \"testFileExtensions\": [\".swift\"],
  \"xunitPath\": \"idchain/reports/latest-tests.xml\",
  \"testCommand\": \"swift test --xunit-output idchain/reports/latest-tests.xml\",
  \"implementationPaths\": [\"Sources/\"],
  \"editAllowlist\": [\"docs/\"]
}"

def configCases : List TestResult :=
  match Config.parse configJson with
  | .error e => [check s!"config parse 失敗: {e}" false]
  | .ok config => [
      checkEq "repoRoot" config.repoRoot "..",
      checkEq "testFileRoots" config.testFileRoots ["Tests"],
      checkEq "testFileExtensions" config.testFileExtensions [".swift"],
      checkEq "xunitPath" config.xunitPath (some "idchain/reports/latest-tests.xml"),
      checkEq "implementationPaths" config.implementationPaths ["Sources/"],
      checkEq "editAllowlist" config.editAllowlist ["docs/"]
    ]

def configDefaultCases : List TestResult :=
  match Config.parse "{}" with
  | .error e => [check s!"空 config parse 失敗: {e}" false]
  | .ok config => [
      checkEq "既定 repoRoot は .." config.repoRoot "..",
      checkEq "既定 xunitPath は none" config.xunitPath (none : Option String),
      checkEq "既定 testCommand は none" config.testCommand (none : Option String)
    ]

def configOracleEnginesJson : String := "{
  \"oracleEngines\": [
    {\"name\": \"engine-a\", \"command\": \"echo {query}\"},
    {\"name\": \"engine-b\", \"command\": \"printf '%s\\n' {query}\"}
  ]
}"

def configOracleEnginesCases : List TestResult :=
  match Config.parse configOracleEnginesJson with
  | .error e => [check s!"oracleEngines 付き config parse 失敗: {e}" false]
  | .ok config => [
      checkEq "oracleEngines 2 件" config.oracleEngines.length 2,
      checkEq "先頭 engine 名" (config.oracleEngines.map (·.name)) ["engine-a", "engine-b"],
      checkEq "先頭 engine command" ((config.oracleEngines.head?).map (·.command)) (some "echo {query}")
    ]

def configErrorCases : List TestResult := [
  check "壊れた JSON は error"
    (match Config.parse "{not json" with
     | .error _ => true
     | .ok _ => false)
]

def swiftSource : String := "import Testing

@Test(\"TC-047-1: 明細3件で小計一致\")
func subtotalMatchesThreeItems() {}

@Test(\"TC-047-2 明細0件で小計0\")
func subtotalZeroItems() {}

// TC-47-9 は strict parse で弾かれる / XTC-099-1 も ID ではない
func helper_TC_not_an_id() {}
"

def tokenizerCases : List TestResult := [
  checkEq "Swift ソースから TC 抽出"
    (extractTestCaseTokens swiftSource) [⟨47, 1⟩, ⟨47, 2⟩],
  checkEq "非 strict 表記は抽出しない"
    (extractTestCaseTokens "TC-47-1 TC-047-01 XTC-047-1 TC-047-1-extra") [],
  checkEq "重複は一意化"
    (extractTestCaseTokens "TC-047-1 TC-047-1") [⟨47, 1⟩],
  checkEq "空文字列" (extractTestCaseTokens "") []
]

def xunitSample : String := "<?xml version=\"1.0\"?>
<testsuites>
  <testsuite name=\"AppTests\">
    <testcase name=\"TC-047-1: 明細3件で小計一致\" time=\"0.01\"/>
    <testcase name=\"TC-047-2 明細0件で小計0\" time=\"0.01\">
      <failure message=\"expected 0 but got 1\">assert failed</failure>
    </testcase>
    <testcase name=\"testNoIdentifier\" time=\"0.02\"/>
    <testcase name=\"TC-048-1 &quot;引用&quot; 付き\" time=\"0.01\">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>"

def xunitCases_ : List XunitCase := parseXunit xunitSample

def xunitParserCases : List TestResult := [
  checkEq "testcase 4 件抽出" xunitCases_.length 4,
  checkEq "self-closing は pass"
    (xunitCases_.find? (·.name == "TC-047-1: 明細3件で小計一致")).isSome true,
  check "TC-047-1 は passed"
    ((xunitCases_.find? (·.name.startsWith "TC-047-1")).any (·.passed)),
  check "failure 子要素は failed"
    ((xunitCases_.find? (·.name.startsWith "TC-047-2")).any (!·.passed)),
  check "skipped 検出"
    ((xunitCases_.find? (·.name.startsWith "TC-048-1")).any (·.skipped)),
  check "XML エンティティ復号 (&quot;)"
    ((xunitCases_.any (·.name == "TC-048-1 \"引用\" 付き")))
]

/-- 突合テスト用の最小 registry: SP-047 (TC 2 件) + SP-048 (TC 1 件、コード未実装)。 -/
def spec47 : Spec := ⟨47, "小計は、明細の合計と常に一致する", 1⟩
def spec48 : Spec := ⟨48, "明細は日付順に整列される", 1⟩

def registryFor : Registry := {
  Registry.empty with
  specs := [spec47, spec48],
  testCases := [
    ⟨⟨47, 1⟩, "明細3件 → 小計 = 合計", .example⟩,
    ⟨⟨47, 2⟩, "明細0件 → 小計 = 0", .example⟩,
    ⟨⟨48, 1⟩, "日付逆順入力 → 整列", .example⟩]
}

def files : List (String × String) := [("Tests/AppTests.swift", swiftSource)]

def resultUnderTest : CrosscheckResult :=
  crosscheck registryFor files (parseXunit "<testsuites>
    <testcase name=\"TC-047-1: 明細3件で小計一致\"/>
    <testcase name=\"TC-047-2 明細0件で小計0\"><failure/></testcase>
    <testcase name=\"testNoIdentifier\"/>
    <testcase name=\"TC-099-9 未知の仕様\"/>
  </testsuites>")

def crosscheckCases : List TestResult := [
  checkEq "孤児テスト (TC ID なし)" resultUnderTest.orphanTests ["testNoIdentifier"],
  checkEq "未知 TC 参照" resultUnderTest.unknownReferences [⟨99, 9⟩],
  checkEq "未実装 TC (コード不在)" resultUnderTest.unimplementedTestCases [⟨48, 1⟩],
  checkEq "未実行 TC" resultUnderTest.unexecutedTestCases ([] : List TestCaseIdentifier),
  checkEq "失敗 TC" resultUnderTest.failedTestCases [⟨47, 2⟩],
  checkEq "成功 TC" resultUnderTest.passedTestCases [⟨47, 1⟩],
  check "構造違反ありで isClean false" (!resultUnderTest.isClean),
  check "コードにあるが未実行の TC 検出"
    (let r := crosscheck registryFor files []
     r.unexecutedTestCases.contains ⟨47, 1⟩ && !r.isClean)
]

-- M3: kind = .oracle の TC は xunit/crosscheck の判定対象から除外する。
def registryWithOracle : Registry := {
  registryFor with
  testCases := registryFor.testCases ++ [⟨⟨47, 3⟩, "オラクル: 小計クエリの多エンジン一致", .oracle⟩]
}

def resultWithOracle : CrosscheckResult :=
  crosscheck registryWithOracle files (parseXunit "<testsuites>
    <testcase name=\"TC-047-1: 明細3件で小計一致\"/>
    <testcase name=\"TC-047-2 明細0件で小計0\"><failure/></testcase>
  </testsuites>")

def oracleExclusionCases : List TestResult := [
  check "oracle TC は未実装判定から除外される"
    (!resultWithOracle.unimplementedTestCases.contains (⟨47, 3⟩ : TestCaseIdentifier)),
  check "oracle TC は未実行判定から除外される"
    (!resultWithOracle.unexecutedTestCases.contains (⟨47, 3⟩ : TestCaseIdentifier)),
  check "oracle TC は成功判定にも含まれない"
    (!resultWithOracle.passedTestCases.contains (⟨47, 3⟩ : TestCaseIdentifier)),
  check "oracle TC は失敗判定にも含まれない"
    (!resultWithOracle.failedTestCases.contains (⟨47, 3⟩ : TestCaseIdentifier)),
  check "oracle TC を追加しても isClean は維持される (48,1 は未実装のまま false)"
    (resultWithOracle.unimplementedTestCases == [(⟨48, 1⟩ : TestCaseIdentifier)]),
  check "コードに oracle TC ID が書かれていても unknownReferences には出ない"
    (let filesWithOracleToken : List (String × String) :=
      files ++ [("Tests/OracleTests.swift", "// TC-047-3 を参照するコメント")]
     let r := crosscheck registryWithOracle filesWithOracleToken []
     !r.unknownReferences.contains (⟨47, 3⟩ : TestCaseIdentifier))
]

def exportCases : List TestResult :=
  let json := exportJson registryFor
  [
    check "export に TC-047-1 が含まれる" ((json.splitOn "TC-047-1").length > 1),
    check "export に SP-048 が含まれる" ((json.splitOn "SP-048").length > 1),
    check "export に kind example が含まれる" ((json.splitOn "example").length > 1)
  ]

def suite : String × List TestResult :=
  ("CrosscheckTests (U7/U8/M3)",
    configCases ++ configDefaultCases ++ configOracleEnginesCases ++ configErrorCases ++ tokenizerCases ++
    xunitParserCases ++ crosscheckCases ++ oracleExclusionCases ++ exportCases)

end Idchain.Tests.CrosscheckTests
