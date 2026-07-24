import Idchain.Approval
import Tests.Framework

/-! U2/U3: アーティファクト構造・正準直列化・FNV-1a・承認ハッシュ束縛のテスト。 -/

namespace Idchain.Tests.ArtifactTests

open Idchain

-- FNV-1a 64bit 既知テストベクタ (http://www.isthe.com/chongo/tech/comp/fnv/)
def hashVectors : List TestResult := [
  checkEq "fnv1a 空文字列 = offset basis" (hashString "") (14695981039346656037 : UInt64),
  checkEq "fnv1a \"a\"" (hashString "a") (0xaf63dc4c8601ec8c : UInt64),
  checkEq "fnv1a \"foobar\"" (hashString "foobar") (0x85944171f73967e8 : UInt64),
  checkEq "fnv1a UTF-8 マルチバイト決定論" (hashString "仕様") (hashString "仕様"),
  check "fnv1a 別内容は別ハッシュ (代表例)" (hashString "SP-047" != hashString "SP-048"),
  checkEq "renderHash 16進表記" (renderHash 0xaf63dc4c8601ec8c) "af63dc4c8601ec8c"
]

def escapeCases : List TestResult := [
  checkEq "パイプのエスケープ" (escapeField "a|b") "a\\|b",
  checkEq "バックスラッシュのエスケープ" (escapeField "a\\b") "a\\\\b",
  checkEq "混合エスケープ" (escapeField "a\\|b") "a\\\\\\|b",
  checkEq "エスケープ不要文字列は不変" (escapeField "小計は明細の合計と一致") "小計は明細の合計と一致",
  checkEq "canonicalJoin 基本形" (canonicalJoin ["SP", "47", "text"]) "SP|47|text",
  checkEq "canonicalJoin フィールド内パイプ" (canonicalJoin ["a|b", "c"]) "a\\|b|c"
]

-- injectivity: フィールド境界を偽装する near-collision ペアが異なる直列化になること
def injectivityCases : List TestResult := [
  check "Problem: statement 内パイプ vs evidence 分割"
    (canonical (Problem.mk 1 "a|b" []) != canonical (Problem.mk 1 "a" [.pending "b"])),
  check "Value: フィールド跨ぎ偽装"
    (canonical (Value.mk 1 "x|2" 3 "c") != canonical (Value.mk 1 "x" 2 "3|c")),
  check "Spec: 番号とテキストの境界"
    (canonical (Spec.mk 47 "text" 1) != canonical (Spec.mk 4 "7|text" 1)),
  check "TestCase: example と property は別直列化"
    (canonical (TestCase.mk ⟨47, 1⟩ "d" .example) != canonical (TestCase.mk ⟨47, 1⟩ "d" .property)),
  check "Learning: hypothesis none と some の区別"
    (canonical (Learning.mk 1 "2026-07-24" none "o") != canonical (Learning.mk 1 "2026-07-24" (some 0) "o"))
]

def sampleSpec : Spec := ⟨47, "小計は、明細の合計と常に一致する", 1⟩

def approvalCases : List TestResult :=
  let approval := approvalFor "lihs" "2026-07-24" "G2: 形式検査パス確認" sampleSpec
  [
    check "承認直後は fresh" (approval.isFresh sampleSpec),
    check "text 変更で承認失効" (!approval.isFresh { sampleSpec with text := "小計は明細合計と一致" }),
    check "featureArea 変更で承認失効" (!approval.isFresh { sampleSpec with featureArea := 2 }),
    checkEq "contentHash は正準直列化ハッシュと一致" approval.contentHash (contentHashOf sampleSpec),
    checkEq "意思の痕跡 (note) が保持される" approval.note "G2: 形式検査パス確認"
  ]

def evidenceCases : List TestResult := [
  check "pending は未充足" ((Evidence.pending "解約率の実測").isPending),
  check "recorded は充足" (!(Evidence.recorded "解約率の実測" "2026-06 顧客インタビュー").isPending)
]

def suite : String × List TestResult :=
  ("ArtifactTests (U2/U3)",
    hashVectors ++ escapeCases ++ injectivityCases ++ approvalCases ++ evidenceCases)

end Idchain.Tests.ArtifactTests
