# z3-tla-playbook 用語集

出典は [方法論の正本](https://gist.github.com/mizchi/db7817e6fc077d567c41cd9d41bb1c53/2133eced8334ed36e47ec4d6e138a46552539256) と、
[現在のローカル実装正本](../../dot_claude/skills/z3-tla-playbook/SKILL.md) である。

| 用語 | 意味 |
|---|---|
| de-facto 仕様 | 文書ではなく、実装が現に決めている振る舞い。宣言された意図と暗黙の挙動を分けて抽出する。 |
| 全列挙 | 有限かつ決定的な入力・状態を通常のプログラムで総当たりする最小の検査手段。 |
| Z3 | 純粋述語、区間、集合、等式などについて、一時点の全入力を扱う SMT solver。 |
| TLA+ / TLC | 状態遷移と非決定性を記述し、全順序・全 interleaving を探索する仕様言語と model checker。 |
| invariant | すべての到達状態で成立すると主張する、名前付きの性質。 |
| witness | Z3 が返す、主張を破る具体的な入力割り当て。 |
| trace | TLC が返す、invariant を破るまでの状態遷移列。 |
| HOLDS | 明示したモデル・制約範囲では性質が破れなかった結果。コード全体の証明ではない。 |
| REFUTED | witness または trace によって主張が破られた結果。 |
| ERROR | 依存不足、構文エラー、timeout、crash。反例とは区別する。 |
| broken variant | ガードや原子性を意図的に外し、検査が赤を検出できることを示す対照。 |
| model↔code gap | 抽象モデルと実装の実際の挙動の差。実データや trace checking で狭める。 |
| ledger | `.formal/ledger.md`。実装の主張、検査結果、反例、質問、残る gap、再実行手順の台帳。 |
