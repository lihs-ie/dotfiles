import Idchain.Checks

/-!
# CLI (対象 repo の IdchainMain が呼ぶライブラリ層)

対象 repo では init が生成する `IdchainMain.lean` が Canon の Registry を注入して
`Idchain.Cli.run` を呼ぶ。engine 単体の `Main.lean` は空 Registry での smoke 用。
-/

namespace Idchain.Cli

open Idchain

def renderViolation (violation : Violation) : String :=
  s!"VIOLATION [{violation.kind.label}] {violation.identifier}: {violation.message}"

def runCheck (registry : Registry) : IO UInt32 := do
  let violations := registry.checkAll
  if violations.isEmpty then
    IO.println "idchain check: 違反 0 件 (ID の鎖は閉じている)"
    return 0
  else
    for violation in violations do
      IO.println (renderViolation violation)
    IO.println s!"idchain check: 違反 {violations.length} 件"
    return 1

def run (registry : Registry) (args : List String) : IO UInt32 := do
  match args with
  | ["check"] => runCheck registry
  | _ => do
    IO.eprintln "usage: idchain check   (export / crosscheck / views / report / approve / init は M1 実装中)"
    return 2

end Idchain.Cli
