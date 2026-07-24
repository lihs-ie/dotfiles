import Idchain.Registry

/-!
# 意味層: SP の形式的意味と無矛盾性証明 (発表 p.42-43)

各 SP はプロジェクト状態型 σ 上の不変条件として解釈される。
**無矛盾性 = 全 SP の不変条件を同時に満たす witness モデルの存在**。
新しい仕様を足すたびに witness と証明の更新が要求されるため、
「新仕様は過去の全仕様との矛盾も検査される」(p.43) が構造的に成立する。

対象 repo の `Canon/Gate.lean` が `ConsistencyProof` のインスタンスを提供しない限り
check exe がコンパイルできない (= 矛盾・曖昧ゼロになるまで実装に進めない、p.42)。
-/

namespace Idchain

/-- SP 一件の形式的解釈。 -/
structure SpecInterpretation (σ : Type) where
  spec : Nat
  invariant : σ → Prop

/-- 仕様群の無矛盾性証明。
`sound`: witness が全解釈の不変条件を満たす。
`complete`: 登録済み全 SP に解釈が提供されている (解釈漏れによる証明回避を防ぐ)。 -/
structure ConsistencyProof (σ : Type) (registry : Registry)
    (interpretations : List (SpecInterpretation σ)) where
  witness : σ
  sound : ∀ interpretation ∈ interpretations, interpretation.invariant witness
  complete : registry.specs.all
    (fun sp => interpretations.any (fun interpretation => interpretation.spec == sp.number)) = true

end Idchain
