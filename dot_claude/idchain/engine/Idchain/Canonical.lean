import Idchain.Artifact
import Idchain.Hash

/-!
# 正準直列化

承認ハッシュの対象となる決定論的直列化。フィールド順は型定義順に固定し、
エスケープ (`\` → `\\`, `|` → `\|`) により injectivity を確保する
(異なる内容が同じ直列化になるとハッシュ束縛承認が偽って有効のままになるため)。
-/

namespace Idchain

def escapeField (s : String) : String :=
  s.foldl (fun acc c =>
    match c with
    | '\\' => acc ++ "\\\\"
    | '|' => acc ++ "\\|"
    | c => acc.push c) ""

def canonicalJoin (fields : List String) : String :=
  String.intercalate "|" (fields.map escapeField)

class Canonical (α : Type) where
  canonical : α → String

export Canonical (canonical)

instance : Canonical Evidence where
  canonical
    | .pending topic => canonicalJoin ["pending", topic]
    | .recorded topic source => canonicalJoin ["recorded", topic, source]

instance : Canonical Problem where
  canonical p :=
    canonicalJoin (["PB", toString p.number, p.statement] ++ p.evidence.map canonical)

instance : Canonical Value where
  canonical v :=
    canonicalJoin ["VL", toString v.number, v.statement, toString v.problem, v.successCriterion]

instance : Canonical FeatureArea where
  canonical fa :=
    canonicalJoin (["FA", toString fa.number, fa.name] ++ fa.values.map toString)

def HypothesisStatus.canonicalString : HypothesisStatus → String
  | .untested => "untested"
  | .supported => "supported"
  | .refuted => "refuted"

instance : Canonical Hypothesis where
  canonical h :=
    canonicalJoin (["HY", toString h.number, h.statement, h.metric, h.threshold,
      toString h.importance, toString h.evidenceStrength, h.status.canonicalString]
      ++ h.problems.map toString)

instance : Canonical Spec where
  canonical sp :=
    canonicalJoin ["SP", toString sp.number, sp.text, toString sp.featureArea]

def TestCaseKind.canonicalString : TestCaseKind → String
  | .example => "example"
  | .property => "property"
  | .oracle => "oracle"
  | .regression => "regression"

instance : Canonical TestCase where
  canonical tc :=
    canonicalJoin ["TC", toString tc.identifier.spec, toString tc.identifier.branch,
      tc.description, tc.kind.canonicalString]

instance : Canonical Learning where
  canonical ll :=
    canonicalJoin ["LL", toString ll.number, ll.date,
      (ll.hypothesis.map toString).getD "", ll.outcome]

def RoadmapItemStatus.canonicalString : RoadmapItemStatus → String
  | .planned => "planned"
  | .inCycle => "inCycle"
  | .done => "done"
  | .dropped => "dropped"

/-- RM は承認対象 (inCycle 化に承認必須のため)。 -/
instance : Canonical RoadmapItem where
  canonical rm :=
    canonicalJoin ["RM", toString rm.number, rm.title, rm.status.canonicalString,
      toString rm.priority, (rm.hypothesis.map toString).getD "", rm.source]

/-- 内容ハッシュ (承認束縛の対象)。 -/
def contentHashOf [Canonical α] (content : α) : UInt64 :=
  hashString (canonical content)

end Idchain
