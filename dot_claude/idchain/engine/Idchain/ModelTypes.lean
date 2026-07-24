/-!
# 実装意味論モデル型: MachineFloat (Must-26)

実装型が浮動小数点の SP は、invariant を書くだけでは非有限値 (±∞ / NaN) の扱いが
曖昧になりやすい。recall-paper SP-001 の教訓: 「〇〇は正の値である」という invariant を
素朴に `0 < x` とだけ書いたところ、実装 (Swift `Double`) では `.infinity` がその条件を
満たしてしまい、意図せず正当な値として通ってしまった。`MachineFloat` はこの非有限値の
扱いをモデル型として明示させることで、同じ齟齬を構造的に防ぐ。
-/

namespace Idchain

/-- 実装型が浮動小数点の場合のモデル型。非有限値の扱いを invariant で明示できる。 -/
inductive MachineFloat where
  | finite (value : Int)
  | infinity
  | negInfinity
  | nan
  deriving Repr, DecidableEq, Inhabited

/-- 有限値 (`finite`) かどうか。`infinity` / `negInfinity` / `nan` はすべて false。 -/
def MachineFloat.isFinite : MachineFloat → Bool
  | .finite _ => true
  | .infinity => false
  | .negInfinity => false
  | .nan => false

/-- `finite v` かつ `0 < v` のときのみ true。非有限値は (無限大であっても) 正値扱いしない
    (recall-paper SP-001 の教訓: 「正の値」が `.infinity` を含み得た)。 -/
def MachineFloat.positiveFinite : MachineFloat → Bool
  | .finite value => 0 < value
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
#guard MachineFloat.positiveFinite .infinity == false
#guard MachineFloat.positiveFinite .negInfinity == false
#guard MachineFloat.positiveFinite .nan == false

end Idchain
