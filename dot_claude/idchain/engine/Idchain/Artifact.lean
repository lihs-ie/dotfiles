import Idchain.Identifier

/-!
# アーティファクト構造体 (データ層)

7 種 (PB/VL/FA/HY/SP/TC/LL) の純データ表現。形式的意味 (SP の invariant) は
意味層 `Idchain.Semantics` が別途束縛し、この層は exe が実行時に処理できる決定可能データのみを持つ。
-/

namespace Idchain

/-- 「要証拠」空欄 (発表 p.69): 確度の低い前提は空欄のまま見える化し、埋まるまでゲートを通さない。 -/
inductive Evidence where
  | pending (topic : String)
  | recorded (topic : String) (source : String)
  deriving Repr, DecidableEq, Inhabited

def Evidence.isPending : Evidence → Bool
  | .pending _ => true
  | .recorded _ _ => false

/-- PB: 顧客課題。 -/
structure Problem where
  number : Nat
  statement : String
  evidence : List Evidence
  deriving Repr, DecidableEq, Inhabited

/-- VL: 提供価値。課題とペアで書き (p.66 原則①)、合格ラインは検証の前に固定する (原則②)。 -/
structure Value where
  number : Nat
  statement : String
  problem : Nat
  successCriterion : String
  deriving Repr, DecidableEq, Inhabited

/-- FA: 機能領域。What と How を繋ぐ (p.66 原則③)。 -/
structure FeatureArea where
  number : Nat
  name : String
  values : List Nat
  deriving Repr, DecidableEq, Inhabited

inductive HypothesisStatus where
  | untested
  | supported
  | refuted
  deriving Repr, DecidableEq, Inhabited

/-- HY: 仮説。反証できる形で書く (p.72: 観測可能指標 + 閾値、重要度×証拠の強さで順序付け)。 -/
structure Hypothesis where
  number : Nat
  statement : String
  metric : String
  threshold : String
  importance : Nat
  evidenceStrength : Nat
  problems : List Nat
  status : HypothesisStatus
  deriving Repr, DecidableEq, Inhabited

/-- SP: 仕様文 (データ層)。発表の `#047`「小計は、明細の合計と常に一致する」に相当。 -/
structure Spec where
  number : Nat
  text : String
  featureArea : Nat
  deriving Repr, DecidableEq, Inhabited

inductive TestCaseKind where
  | example
  | property
  | oracle
  | regression
  deriving Repr, DecidableEq, Inhabited

/-- TC: テストケース。仕様から導出する (p.40: コードから作らせると実装追認テストになる)。 -/
structure TestCase where
  identifier : TestCaseIdentifier
  description : String
  kind : TestCaseKind
  deriving Repr, DecidableEq, Inhabited

/-- LL: 学び台帳。外れた仮説も消さずに記録する (p.73、append-only)。 -/
structure Learning where
  number : Nat
  date : String
  hypothesis : Option Nat
  outcome : String
  deriving Repr, DecidableEq, Inhabited

/-- オラクルクエリ: kind = .oracle の TC に対応し、多エンジンに投げる問い合わせ文字列を持つ。 -/
structure OracleQuery where
  testCase : TestCaseIdentifier
  query : String
  deriving Repr, DecidableEq, Inhabited

/-- ペアワイズ生成の因子 (パラメータ) とその水準一覧。 -/
structure Factor where
  name : String
  levels : List String
  deriving Repr, DecidableEq, Inhabited

/-- ベンチマーク定義。stdout 最終行が整数ミリ秒であるコマンドを実行し、閾値で赤黄緑を判定する。 -/
structure Benchmark where
  name : String
  command : String
  greenThresholdMilliseconds : Nat
  redThresholdMilliseconds : Nat
  deriving Repr, DecidableEq, Inhabited

inductive RoadmapItemStatus where
  | planned
  | inCycle
  | done
  | dropped
  deriving Repr, DecidableEq, Inhabited

/-- RM: ロードマップ項目 (発表 p.22/73)。dropped も削除禁止 (意思の痕跡)。 -/
structure RoadmapItem where
  number : Nat
  title : String
  status : RoadmapItemStatus
  priority : Nat            -- 小さいほど先 (次に潰す順)
  hypothesis : Option Nat   -- 関連 HY
  source : String           -- 出典: "discovery" / "LL-001" / "bench:<ベンチ名>" 等
  deriving Repr, DecidableEq, Inhabited

/-- SP の意味一致レビュー (Must-24)。SP 内容ハッシュに束縛され、SP 文変更で失効。 -/
structure SemanticReview where
  spec : Nat
  reviewedBy : String       -- 実施エージェント/モデル名
  date : String
  verdict : Bool            -- true = 多義性なし・invariant と一致
  findings : String         -- 指摘 (verdict true でも「境界値明示を確認」等を書く)
  contentHash : UInt64
  deriving Repr, DecidableEq, Inhabited

end Idchain
