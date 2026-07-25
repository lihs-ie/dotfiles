------------------------- MODULE Example__StaleRead -------------------------
(* broken variant — Example.tla から **判定と書き込みを分離しただけ** の版。      *)
(* run-checks.sh はこれが反例で捕まる (VIOLATE) ことを要求する。捕まらないなら    *)
(* Example.tla 側の緑は「何も検証していない緑」である。                          *)

EXTENDS Integers

CONSTANTS Cap, Workers

VARIABLES served, pc, seen

vars == <<served, pc, seen>>

Init == /\ served = 0
        /\ pc = [w \in Workers |-> "read"]
        /\ seen = [w \in Workers |-> 0]

\* 読んで (Read) → 判定して書く (Commit) が別ステップ = read-modify-write レース
Read(w) == /\ pc[w] = "read"
           /\ seen' = [seen EXCEPT ![w] = served]
           /\ pc' = [pc EXCEPT ![w] = "write"]
           /\ UNCHANGED served

Commit(w) == /\ pc[w] = "write"
             /\ seen[w] < Cap
             /\ served' = served + 1
             /\ pc' = [pc EXCEPT ![w] = "done"]
             /\ UNCHANGED seen

Abort(w) == /\ pc[w] = "write"
            /\ seen[w] >= Cap
            /\ pc' = [pc EXCEPT ![w] = "done"]
            /\ UNCHANGED <<served, seen>>

Terminating == /\ \A w \in Workers : pc[w] = "done"
               /\ UNCHANGED vars

Next == \/ \E w \in Workers : Read(w) \/ Commit(w) \/ Abort(w)
        \/ Terminating

Spec == Init /\ [][Next]_vars

NeverOverCap == served <= Cap

=============================================================================
