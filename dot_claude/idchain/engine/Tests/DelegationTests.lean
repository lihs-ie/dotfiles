import Idchain.Delegation
import Tests.Framework

namespace Idchain.Tests.DelegationTests
open Idchain

def contract : DelegationContract := {
  identifier := "delivery-1", outcome := "observable delivery",
  criteria := ["acceptance"], nonGoals := ["unrelated hardening"],
  targets := [{ target := "SP-001", criterion := "acceptance" }],
  anchors := [{ target := "RM-001", hash := "frozen" }],
  agents := ["codex"], decisions := ["prepare", "review", "approve", "complete"],
  preparationBudget := 1, reviewBudget := 1, decisionBudget := 2,
  stopConditions := ["scope delta requires human authorization"] }

def usage : DelegationUse := {
  sequence := 1, contract := "delivery-1", contractHash := "hash", agent := "codex",
  decision := "prepare", target := "SP-001", criterion := "acceptance",
  date := "2026-09-08", note := "prepare fixed scope" }

def suite : String × List TestResult := ("DelegationTests", [
  check "TC-delegation-1 valid bounded preparation" (validateDelegationUse contract [] usage).isOk,
  check "TC-delegation-2 no budget reset" !(validateDelegationUse contract [usage] { usage with sequence := 2 }).isOk,
  check "TC-delegation-3 no target growth" !(validateDelegationUse contract [] { usage with target := "SP-002" }).isOk,
  check "TC-delegation-4 no criterion reassignment" !(validateDelegationUse contract [] { usage with criterion := "other" }).isOk,
  check "TC-delegation-5 no agent impersonation" !(validateDelegationUse contract [] { usage with agent := "human" }).isOk,
  check "TC-delegation-6 no sequence reuse" !(validateDelegationUse contract [usage] usage).isOk,
  check "TC-delegation-7 completion needs evidence" !(validateDelegationUse contract [] { usage with decision := "complete" }).isOk,
  check "TC-delegation-8 non-goals required" !(validateDelegationContract { contract with nonGoals := [] }).isOk,
  check "TC-delegation-9 zero preparation is valid" (validateDelegationContract { contract with preparationBudget := 0 }).isOk,
  check "TC-delegation-10 zero preparation forbids use" !(validateDelegationUse { contract with preparationBudget := 0 } [] usage).isOk,
  check "TC-delegation-11 exact review reservation required" !(validateDelegationUse contract []
    { usage with decision := "approve", evidence := [{ path := "receipt", hash := "digest" }] }).isOk,
  check "TC-delegation-12 decisions never grow" !(validateDelegationUse contract []
    { usage with decision := "expand" }).isOk
])
end Idchain.Tests.DelegationTests
