import Idchain.ModelTypes
import Tests.Framework

/-! Must-26: MachineFloat (isFinite/positiveFinite) のランタイムテスト。#guard の代表例を網羅する。 -/

namespace Idchain.Tests.ModelTypesTests

open Idchain

def isFiniteCases : List TestResult := [
  check "finite は isFinite" ((MachineFloat.finite 3).isFinite),
  check "finite 0 も isFinite" ((MachineFloat.finite 0).isFinite),
  check "負の finite も isFinite" ((MachineFloat.finite (-5)).isFinite),
  check "infinity は isFinite ではない" (!MachineFloat.infinity.isFinite),
  check "negInfinity は isFinite ではない" (!MachineFloat.negInfinity.isFinite),
  check "nan は isFinite ではない" (!MachineFloat.nan.isFinite)
]

def positiveFiniteCases : List TestResult := [
  check "正の finite は positiveFinite" ((MachineFloat.finite 3).positiveFinite),
  check "0 は positiveFinite ではない (境界値)" (!(MachineFloat.finite 0).positiveFinite),
  check "負の finite は positiveFinite ではない" (!(MachineFloat.finite (-1)).positiveFinite),
  check "infinity は positiveFinite ではない (recall-paper SP-001 の教訓)"
    (!MachineFloat.infinity.positiveFinite),
  check "negInfinity は positiveFinite ではない" (!MachineFloat.negInfinity.positiveFinite),
  check "nan は positiveFinite ではない" (!MachineFloat.nan.positiveFinite)
]

def suite : String × List TestResult :=
  ("ModelTypesTests (Must-26)", isFiniteCases ++ positiveFiniteCases)

end Idchain.Tests.ModelTypesTests
