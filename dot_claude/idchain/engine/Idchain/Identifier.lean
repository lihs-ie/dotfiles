/-!
# idchain ID 体系

統一プレフィックス族 PB/VL/FA/HY/SP/LL (SimpleIdentifier) + TC (TestCaseIdentifier、親 SP 番号を型として保持)。
表記: ゼロ埋め 3 桁 (`SP-047`)、1000 以上はそのまま (`SP-1047`)。TC は `TC-<SP番号>-<枝番>`。
parse は renderer の像のみ受理する (往復同一性が定義から成立)。
-/

namespace Idchain

/-- アーティファクト種別 (TC は複合 ID のため `TestCaseIdentifier` として別型)。 -/
inductive ArtifactKind where
  | pb
  | vl
  | fa
  | hy
  | sp
  | ll
  | rm
  deriving Repr, DecidableEq, Hashable, Inhabited

def ArtifactKind.prefixString : ArtifactKind → String
  | .pb => "PB"
  | .vl => "VL"
  | .fa => "FA"
  | .hy => "HY"
  | .sp => "SP"
  | .ll => "LL"
  | .rm => "RM"

def ArtifactKind.all : List ArtifactKind := [.pb, .vl, .fa, .hy, .sp, .ll, .rm]

def ArtifactKind.ofPrefix? (s : String) : Option ArtifactKind :=
  ArtifactKind.all.find? (·.prefixString == s)

/-- PB/VL/FA/HY/SP/LL の単純 ID。 -/
structure SimpleIdentifier where
  kind : ArtifactKind
  number : Nat
  deriving Repr, DecidableEq, Hashable, Inhabited

/-- テストケース ID `TC-<SP番号>-<枝番>`。導出元 SP 番号を構造として持つ。 -/
structure TestCaseIdentifier where
  spec : Nat
  branch : Nat
  deriving Repr, DecidableEq, Hashable, Inhabited

/-- 全 ID の直和。 -/
inductive AnyIdentifier where
  | simple (identifier : SimpleIdentifier)
  | testCase (identifier : TestCaseIdentifier)
  deriving Repr, DecidableEq, Hashable, Inhabited

/-- 3 桁ゼロ埋め (1000 以上はそのまま)。 -/
def padNumber (n : Nat) : String :=
  let s := toString n
  if s.length >= 3 then s
  else String.ofList (List.replicate (3 - s.length) '0') ++ s

def SimpleIdentifier.render (identifier : SimpleIdentifier) : String :=
  s!"{identifier.kind.prefixString}-{padNumber identifier.number}"

def TestCaseIdentifier.render (identifier : TestCaseIdentifier) : String :=
  s!"TC-{padNumber identifier.spec}-{identifier.branch}"

def AnyIdentifier.render : AnyIdentifier → String
  | .simple identifier => identifier.render
  | .testCase identifier => identifier.render

/-- `padNumber` の像のみ受理する strict な数値パース (冗長ゼロ埋めは `none`)。 -/
def parsePaddedNumber (s : String) : Option Nat := do
  let n ← s.toNat?
  guard (s == padNumber n)
  pure n

/-- 枝番パース (ゼロ埋めなし。`"01"` は `none`)。 -/
def parseBareNumber (s : String) : Option Nat := do
  let n ← s.toNat?
  guard (s == toString n)
  pure n

def SimpleIdentifier.parse (s : String) : Option SimpleIdentifier :=
  match s.splitOn "-" with
  | [prefixPart, numberPart] => do
    let kind ← ArtifactKind.ofPrefix? prefixPart
    let number ← parsePaddedNumber numberPart
    pure ⟨kind, number⟩
  | _ => none

def TestCaseIdentifier.parse (s : String) : Option TestCaseIdentifier :=
  match s.splitOn "-" with
  | ["TC", specPart, branchPart] => do
    let spec ← parsePaddedNumber specPart
    let branch ← parseBareNumber branchPart
    pure ⟨spec, branch⟩
  | _ => none

def AnyIdentifier.parse (s : String) : Option AnyIdentifier :=
  (SimpleIdentifier.parse s).map .simple <|> (TestCaseIdentifier.parse s).map .testCase

-- コンパイル時ロック (代表例)
#guard SimpleIdentifier.render ⟨.sp, 47⟩ == "SP-047"
#guard TestCaseIdentifier.render ⟨47, 1⟩ == "TC-047-1"
#guard SimpleIdentifier.parse "SP-047" == some ⟨.sp, 47⟩
#guard SimpleIdentifier.parse "SP-47" == (none : Option SimpleIdentifier)
#guard TestCaseIdentifier.parse "TC-047-12" == some ⟨47, 12⟩
#guard AnyIdentifier.parse "TC-047-2" == some (.testCase ⟨47, 2⟩)

end Idchain
