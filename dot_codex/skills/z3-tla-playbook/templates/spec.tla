---------------------------- MODULE Example ----------------------------
(* TLA+ 仕様の雛形 — 「時間を通じて、全順序・全 interleaving」の主張を検査する。   *)
(*                                                                        *)
(* この例は「上限 Cap まで配信する」を **判定と書き込みが 1 ステップ (atomic)** で   *)
(* 起きるモデルとして書いたもの。NeverOverCap は成立する。                      *)
(* 対照 (broken/Example__StaleRead.tla) は判定と書き込みを分離しただけで          *)
(* 上限が破れる — その差分が「条件付き書き込みが load-bearing である」証拠になる。 *)

EXTENDS Integers

CONSTANTS Cap, Workers

VARIABLES served, pc

vars == <<served, pc>>

Init == /\ served = 0
        /\ pc = [w \in Workers |-> "ready"]

\* 判定 (served < Cap) と加算を同一ステップで行う = 条件付き書き込み
Serve(w) == /\ pc[w] = "ready"
            /\ served < Cap
            /\ served' = served + 1
            /\ pc' = [pc EXCEPT ![w] = "done"]

Reject(w) == /\ pc[w] = "ready"
             /\ served >= Cap
             /\ pc' = [pc EXCEPT ![w] = "done"]
             /\ UNCHANGED served

\* 全員 done で停止 (deadlock 報告を避けるための標準イディオム)
Terminating == /\ \A w \in Workers : pc[w] = "done"
               /\ UNCHANGED vars

Next == \/ \E w \in Workers : Serve(w) \/ Reject(w)
        \/ Terminating

Spec == Init /\ [][Next]_vars

\* 証明したい性質には名前を付ける (レビューで会話できる単位にする)
NeverOverCap == served <= Cap

=============================================================================
