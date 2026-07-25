/-!
# idchain engine テストハーネス

runtime assertion の最小フレームワーク。全 pass で exit 0 / 1 件でも fail で exit 1。
コンパイル時に固定できる性質は各テストモジュールで `#guard` も併用する。
-/

namespace Idchain.Tests

structure TestResult where
  name : String
  passed : Bool
  message : String := ""

def check (name : String) (cond : Bool) (message : String := "") : TestResult :=
  { name, passed := cond, message }

def checkEq [BEq α] [Repr α] (name : String) (actual expected : α) : TestResult :=
  if actual == expected then
    { name, passed := true }
  else
    { name, passed := false, message := s!"expected {repr expected}, got {repr actual}" }

def runAll (suites : List (String × List TestResult)) : IO UInt32 := do
  let mut total := 0
  let mut failures := 0
  for (suiteName, results) in suites do
    IO.println s!"== {suiteName}"
    for r in results do
      total := total + 1
      if r.passed then
        IO.println s!"  PASS {r.name}"
      else
        failures := failures + 1
        let suffix := if r.message.isEmpty then "" else s!" — {r.message}"
        IO.println s!"  FAIL {r.name}{suffix}"
  IO.println s!"{total - failures}/{total} passed"
  return if failures == 0 then 0 else 1

end Idchain.Tests
