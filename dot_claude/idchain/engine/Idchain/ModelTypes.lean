/-!
# 実装意味論モデル型: MachineFloat (Must-26)

実装型が浮動小数点の SP は、invariant を書くだけでは非有限値 (±∞ / NaN) の扱いが
曖昧になりやすい。recall-paper SP-001 の教訓: 「〇〇は正の値である」という invariant を
素朴に `0 < x` とだけ書いたところ、実装 (Swift `Double`) では `.infinity` がその条件を
満たしてしまい、意図せず正当な値として通ってしまった。`MachineFloat` はこの非有限値の
扱いをモデル型として明示させることで、同じ齟齬を構造的に防ぐ。
-/

namespace Idchain

/-- 実装型が浮動小数点の場合のモデル型。非有限値の扱いを invariant で明示できる。

有限値は有理数対 `finite numerator denominator` で表す (分母既定 1 — 整数は `.finite 21600` のまま)。
Lean の Int/Nat は任意精度のため、denormal を含む**すべての有限 IEEE754 値を正確に表現できる**
(例: `.leastNormalMagnitude` ≈ 2.225e-308 は `.finite 22250738585072014 (10 ^ 324)` 級の対で表せる)。
独立意味検査の指摘 (Int 単独では極小正値を 0 に潰してしまい TC の境界期待と齟齬) への対応。 -/
inductive MachineFloat where
  | finite (numerator : Int) (denominator : Nat := 1)
  | infinity
  | negInfinity
  | nan
  deriving Repr, DecidableEq, Inhabited

/-- 有限値 (`finite`) かどうか。`infinity` / `negInfinity` / `nan` はすべて false。 -/
def MachineFloat.isFinite : MachineFloat → Bool
  | .finite _ _ => true
  | .infinity => false
  | .negInfinity => false
  | .nan => false

/-- `finite n d` かつ `0 < n` かつ `0 < d` のときのみ true (分母 0 は不正表現として false)。
    非有限値は (無限大であっても) 正値扱いしない
    (recall-paper SP-001 の教訓: 「正の値」が `.infinity` を含み得た)。 -/
def MachineFloat.positiveFinite : MachineFloat → Bool
  | .finite numerator denominator => 0 < numerator && 0 < denominator
  | .infinity => false
  | .negInfinity => false
  | .nan => false

#guard MachineFloat.isFinite (.finite 3) == true
#guard MachineFloat.isFinite (.finite 0) == true
#guard MachineFloat.isFinite .infinity == false
#guard MachineFloat.isFinite .negInfinity == false
#guard MachineFloat.isFinite .nan == false
#guard MachineFloat.positiveFinite (.finite 3) == true
#guard MachineFloat.positiveFinite (.finite 0) == false
#guard MachineFloat.positiveFinite (.finite (-1)) == false
-- 極小正値 (denormal 級) も正確に「正の有限値」として表現できる
#guard MachineFloat.positiveFinite (.finite 1 (10 ^ 308)) == true
#guard MachineFloat.positiveFinite (.finite (-1) 2) == false
#guard MachineFloat.positiveFinite (.finite 1 0) == false
#guard MachineFloat.positiveFinite .infinity == false
#guard MachineFloat.positiveFinite .negInfinity == false
#guard MachineFloat.positiveFinite .nan == false

end Idchain
