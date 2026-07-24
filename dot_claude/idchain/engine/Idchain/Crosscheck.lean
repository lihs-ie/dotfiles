import Idchain.Registry

/-!
# TC ⇄ 実テスト双方向突合 (U8、発表 p.37)

Lean 正本の TC 一覧と、実テストコード (TC ID 注釈規約) + xunit 実行結果を双方向に突合する。
- 仕様に紐づいていないテスト (orphan test): xunit のテスト名に TC ID がない
- 未知の TC を名乗る参照 (unknown): コード/結果に現れた TC ID が正本にない
- 未実装 TC (unimplemented): 正本の TC がどのテストファイルにも現れない
- 未実行 TC (unexecuted): コードには現れるが xunit 結果に現れない

注釈規約: テスト名または表示名に TC ID を区切り文字 (英数字とハイフン以外) で
囲んで埋め込む (例: `@Test("TC-047-1: 明細3件で小計一致")`)。
-/

namespace Idchain

private def flushToken (tokens : List String) (current : List Char) : List String :=
  if current.isEmpty then tokens else tokens ++ [String.ofList current.reverse]

/-- 英数字とハイフンの連続をトークンとして切り出す。 -/
private def tokenize (content : String) : List String :=
  let (tokens, current) := content.foldl
    (fun (state : List String × List Char) c =>
      let (tokens, current) := state
      if c.isAlphanum || c == '-' then (tokens, c :: current)
      else (flushToken tokens current, []))
    ([], [])
  flushToken tokens current

/-- 英数字とハイフンのトークンに分解し、strict parse に成功したものだけを TC ID とみなす。 -/
def extractTestCaseTokens (content : String) : List TestCaseIdentifier :=
  ((tokenize content).filterMap TestCaseIdentifier.parse).eraseDups

structure XunitCase where
  name : String
  passed : Bool
  skipped : Bool
  deriving Repr, DecidableEq, Inhabited

private def xmlUnescape (s : String) : String :=
  ((((s.replace "&quot;" "\"").replace "&apos;" "'").replace "&lt;" "<").replace "&gt;" ">").replace "&amp;" "&"

/-- 引用符状態を追跡してタグ終端 `>` の位置を探す。 -/
private def findTagEnd : List Char → Bool → Nat → Option Nat
  | [], _, _ => none
  | c :: rest, inQuote, index =>
    if c == '"' then findTagEnd rest (!inQuote) (index + 1)
    else if c == '>' && !inQuote then some index
    else findTagEnd rest inQuote (index + 1)

/-- タグ文字列から ` name="..."` 属性値を取り出す (単/二重引用符対応、エンティティ復号)。 -/
private def nameAttribute (tag : String) : Option String := do
  let rest ← (tag.splitOn " name=")[1]?
  let chars := rest.toList
  let quote ← chars.head?
  guard (quote == '"' || quote == '\'')
  let value := String.ofList ((chars.drop 1).takeWhile (· != quote))
  pure (xmlUnescape value)

/-- xunit XML の最小パーサ (testcase 要素の name / failure・error・skipped 子要素のみ解釈)。 -/
def parseXunit (xml : String) : List XunitCase :=
  ((xml.splitOn "<testcase").drop 1).filterMap fun chunk => do
    let chars := chunk.toList
    let tagEnd ← findTagEnd chars false 0
    let tagChars := chars.take tagEnd
    let name ← nameAttribute (String.ofList tagChars)
    let selfClosing := (tagChars.reverse.dropWhile Char.isWhitespace).head? == some '/'
    let body := if selfClosing then ""
      else ((String.ofList (chars.drop (tagEnd + 1))).splitOn "</testcase>").headD ""
    let failed := (body.splitOn "<failure").length > 1 || (body.splitOn "<error").length > 1
    let skipped := (body.splitOn "<skipped").length > 1
    pure { name, passed := !failed && !skipped, skipped }

structure CrosscheckResult where
  orphanTests : List String
  unknownReferences : List TestCaseIdentifier
  unimplementedTestCases : List TestCaseIdentifier
  unexecutedTestCases : List TestCaseIdentifier
  failedTestCases : List TestCaseIdentifier
  passedTestCases : List TestCaseIdentifier
  deriving Repr, Inhabited

/-- 構造違反 (孤児・未知・未実装・未実行) がないか。テストの成否は report の管轄。 -/
def CrosscheckResult.isClean (result : CrosscheckResult) : Bool :=
  result.orphanTests.isEmpty && result.unknownReferences.isEmpty &&
  result.unimplementedTestCases.isEmpty && result.unexecutedTestCases.isEmpty

def crosscheck (registry : Registry) (fileContents : List (String × String))
    (xunitCases : List XunitCase) : CrosscheckResult :=
  -- kind = .oracle の TC は oracle exe で検証されるため、xunit ベースの
  -- 未実装/未実行/成功/失敗判定 (canonIdentifiers 由来) からは除外する。
  -- ただし「既知の ID」としては扱う (allIdentifiers) ので unknownReferences には出ない。
  let allIdentifiers := registry.testCases.map (·.identifier)
  let canonIdentifiers :=
    (registry.testCases.filter (·.kind != TestCaseKind.oracle)).map (·.identifier)
  let codeIdentifiers :=
    (fileContents.flatMap fun (_, content) => extractTestCaseTokens content).eraseDups
  let executed := xunitCases.filter (fun testCase => !testCase.skipped)
  let executedReferences := executed.map fun testCase => (testCase, extractTestCaseTokens testCase.name)
  let orphanTests :=
    (executedReferences.filter fun (_, identifiers) => identifiers.isEmpty).map (·.1.name)
  let xunitIdentifiers := (executedReferences.flatMap (·.2)).eraseDups
  let unknownReferences :=
    ((codeIdentifiers ++ xunitIdentifiers).eraseDups).filter (!allIdentifiers.contains ·)
  let unimplementedTestCases := canonIdentifiers.filter (!codeIdentifiers.contains ·)
  let unexecutedTestCases := canonIdentifiers.filter fun identifier =>
    codeIdentifiers.contains identifier && !xunitIdentifiers.contains identifier
  let failedIdentifiers :=
    ((executedReferences.filter fun (testCase, _) => !testCase.passed).flatMap (·.2)).eraseDups
  let failedTestCases := canonIdentifiers.filter (failedIdentifiers.contains ·)
  let passedTestCases := canonIdentifiers.filter fun identifier =>
    xunitIdentifiers.contains identifier && !failedIdentifiers.contains identifier
  { orphanTests, unknownReferences, unimplementedTestCases,
    unexecutedTestCases, failedTestCases, passedTestCases }

end Idchain
