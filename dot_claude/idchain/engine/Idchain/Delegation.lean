import Idchain.Approve
import Lean.Data.Json

/-! Bounded delegation is repository-local policy, not authentication of a human.
    Committed grants are immutable; a committed append-only ledger serializes uses.
    Repository owners able to rewrite code/history remain outside this boundary. -/
namespace Idchain
open Lean

structure DelegationTarget where
  target : String
  criterion : String
  deriving Repr, BEq, FromJson, ToJson

structure DelegationAnchor where
  target : String
  hash : String
  deriving Repr, BEq, FromJson, ToJson

structure DelegationContract where
  identifier : String
  outcome : String
  criteria : List String
  nonGoals : List String
  targets : List DelegationTarget
  anchors : List DelegationAnchor
  agents : List String
  decisions : List String
  preparationBudget : Nat
  reviewBudget : Nat
  decisionBudget : Nat
  stopConditions : List String
  deriving Repr, BEq, FromJson, ToJson

structure DelegationGrant where
  contract : DelegationContract
  authorizedBy : String
  date : String
  note : String
  confirmedHash : String
  deriving Repr, BEq, FromJson, ToJson

structure DelegationEvidence where
  path : String
  hash : String
  deriving Repr, BEq, FromJson, ToJson

structure DelegationUse where
  sequence : Nat
  contract : String
  contractHash : String
  agent : String
  decision : String
  target : String
  criterion : String
  date : String
  note : String
  contentHash : String := ""
  requiresCompletion : Bool := false
  evidence : List DelegationEvidence := []
  deriving Repr, BEq, FromJson, ToJson

/-- A separate reviewer binds scope assessment to this exact contract and content. -/
structure DelegationScopeReview where
  contractHash : String
  target : String
  criterion : String
  contentHash : String
  reviewedBy : String
  verdict : Bool
  findings : String
  deriving Repr, FromJson, ToJson

structure DelegationAcceptance where
  criterion : String
  evidence : DelegationEvidence
  deriving Repr, FromJson, ToJson

structure DelegationCompletion where
  contractHash : String
  report : DelegationEvidence
  acceptance : List DelegationAcceptance
  deriving Repr, FromJson, ToJson

def delegationContractHash (contract : DelegationContract) : String :=
  renderHash (hashString (toJson contract).compress)

private def nonempty (value : String) : Bool := !value.trimAscii.toString.isEmpty

def validateDelegationContract (contract : DelegationContract) : Except String Unit := do
  unless nonempty contract.identifier && contract.identifier.toList.all
      (fun c => c.isAlphanum || c == '-' || c == '_') do throw "invalid contract identifier"
  unless nonempty contract.outcome && !contract.criteria.isEmpty &&
      contract.criteria.all nonempty && !contract.nonGoals.isEmpty &&
      contract.nonGoals.all nonempty && !contract.stopConditions.isEmpty &&
      contract.stopConditions.all nonempty do throw "outcome/criteria/nonGoals/stopConditions required"
  unless contract.criteria.eraseDups == contract.criteria do throw "duplicate criteria"
  unless !contract.targets.isEmpty && contract.targets.all (fun t =>
      (SimpleIdentifier.parse t.target).isSome && contract.criteria.contains t.criterion) do
    throw "exact target and criterion mapping required"
  unless (contract.targets.map (·.target)).eraseDups.length == contract.targets.length do
    throw "duplicate target"
  unless !contract.anchors.isEmpty && contract.anchors.all (fun a =>
      (SimpleIdentifier.parse a.target).isSome && nonempty a.hash) do throw "frozen upstream anchors required"
  unless !contract.agents.isEmpty && contract.agents.all nonempty do throw "actual agent names required"
  unless !contract.decisions.isEmpty && contract.decisions.all
      (["prepare", "review", "approve", "complete"].contains ·) do throw "invalid allowed decisions"
  unless contract.decisionBudget > 0 do throw "finite positive decision budget required"

def validateDelegationUse (contract : DelegationContract) (ledger : List DelegationUse)
    (usage : DelegationUse) : Except String Unit := do
  validateDelegationContract contract
  unless usage.sequence == ledger.length + 1 do throw "ledger sequence reuse or gap"
  unless usage.contract == contract.identifier && contract.agents.contains usage.agent do
    throw "unauthorized contract or agent"
  unless contract.decisions.contains usage.decision do throw "decision not delegated"
  unless contract.targets.any (fun t => t.target == usage.target && t.criterion == usage.criterion) do
    throw "scope or criterion delta requires human authorization"
  unless nonempty usage.date && nonempty usage.note do throw "decision trace required"
  let previous := ledger.filter (·.contract == contract.identifier)
  unless !previous.any (·.decision == "complete") do throw "contract already completed"
  let spent := previous.filter (·.decision == usage.decision) |>.length
  if usage.decision == "prepare" then
    unless spent < contract.preparationBudget do throw "preparation budget exhausted"
  else if usage.decision == "review" then
    unless spent < contract.reviewBudget do throw "review budget exhausted"
    unless contract.preparationBudget == 0 ||
        previous.any (fun u => u.decision == "prepare" && u.target == usage.target) do
      throw "reserve preparation before review"
  else
    unless (previous.filter (fun u => u.decision == "approve" || u.decision == "complete")).length
        < contract.decisionBudget do throw "decision budget exhausted"
    unless !usage.evidence.isEmpty do throw "approval/completion evidence required"
    if usage.decision == "approve" then
      unless previous.any (fun u => u.decision == "review" && u.target == usage.target &&
          u.contentHash == usage.contentHash && u.agent != usage.agent) do
        throw "consume review budget for exact content before approval"

namespace Delegation

def ledgerPath : System.FilePath := ".delegation/ledger.json"
def grantPath (identifier : String) : System.FilePath :=
  ".delegation/contracts" / (identifier ++ ".json")

def readJson [FromJson α] (path : System.FilePath) : IO α := do
  match Json.parse (← IO.FS.readFile path) >>= fromJson? with
  | .ok value => return value
  | .error error => throw (IO.userError s!"{path}: {error}")

def git (args : Array String) : IO String := do
  let result ← IO.Process.output { cmd := "git", args }
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout.trimAscii.toString

/-- Symlinks and non-repository paths cannot serve as policy/evidence. -/
def tracked (path : System.FilePath) : IO Unit := do
  let name := path.toString
  unless !path.isAbsolute && !(name.splitOn "/").any (· == "..") do
    throw (IO.userError "repository-relative normal file required")
  let info ← path.symlinkMetadata
  unless info.type == .file do throw (IO.userError "regular file required")
  let mode ← git #["ls-files", "--stage", "--", name]
  unless mode.startsWith "100644 " || mode.startsWith "100755 " do
    throw (IO.userError s!"{path}: tracked normal file required")
  discard <| git #["diff", "--exit-code", "HEAD", "--", name]

def loadLedger : IO (List DelegationUse) := do
  if ← ledgerPath.pathExists then readJson ledgerPath else return []

/-- A use may be appended to HEAD, never rewritten or removed. Next mutation requires commit. -/
def verifyLedgerHistory (ledger : List DelegationUse) (writing : Bool) : IO Unit := do
  let directoryPrefix ← git #["rev-parse", "--show-prefix"]
  let history ← git #["log", "--reverse", "--format=%H", "--", ledgerPath.toString]
  let mut committed : List DelegationUse := []
  for commit in (history.splitOn "\n").filter (!·.isEmpty) do
    let snapshot ← git #["show", s!"{commit}:{directoryPrefix}{ledgerPath}"]
    let entries : List DelegationUse ← match Json.parse snapshot >>= fromJson? with
      | .ok value => pure value
      | .error error => throw (IO.userError error)
    unless entries.take committed.length == committed do
      throw (IO.userError "committed ledger rewrite forbidden")
    committed := entries
  let result ← IO.Process.output { cmd := "git", args := #["show", s!"HEAD:{directoryPrefix}{ledgerPath}"] }
  let baseline : List DelegationUse ← if result.exitCode == 0 then
      match Json.parse result.stdout >>= fromJson? with
      | .ok value => pure value
      | .error error => throw (IO.userError error)
    else pure []
  unless ledger.take baseline.length == baseline do throw (IO.userError "ledger reset/rewrite forbidden")
  unless !writing || ledger == baseline do throw (IO.userError "commit previous use before another decision")
  unless ledger.length ≤ baseline.length + 1 do throw (IO.userError "uncommitted multiple uses forbidden")

def loadGrant (identifier : String) : IO DelegationGrant := do
  unless nonempty identifier && identifier.toList.all (fun c => c.isAlphanum || c == '-' || c == '_') do
    throw (IO.userError "invalid contract identifier")
  let path := grantPath identifier
  tracked path
  let grant : DelegationGrant ← readJson path
  unless grant.contract.identifier == identifier && grant.confirmedHash == delegationContractHash grant.contract &&
      nonempty grant.authorizedBy && nonempty grant.note && !grant.contract.agents.contains grant.authorizedBy do
    throw (IO.userError "missing or mutated human grant")
  -- The first committed grant is authoritative even if a later commit edits it.
  let commits := (← git #["log", "--format=%H", "--", path.toString]).splitOn "\n"
  let oldest := commits.getLast!
  let directoryPrefix ← git #["rev-parse", "--show-prefix"]
  let original ← git #["show", s!"{oldest}:{directoryPrefix}{path}"]
  unless original == (← IO.FS.readFile path).trimAscii.toString do
    throw (IO.userError "committed grant mutation forbidden; obtain a new human grant")
  return grant

def verifyAnchors (registry : Registry) (contract : DelegationContract) : IO Unit := do
  for anchor in contract.anchors do
    let some target := SimpleIdentifier.parse anchor.target | throw (IO.userError "invalid anchor")
    unless (registry.contentHashFor target).map renderHash == some anchor.hash do
      throw (IO.userError "stale upstream grant anchor")
    unless registry.approvals.any (fun record => record.target == target &&
        record.approval.authority == .human && renderHash record.approval.contentHash == anchor.hash) do
      throw (IO.userError "upstream anchor must have human approval")

def verifyEvidence (evidence : DelegationEvidence) : IO Unit := do
  tracked evidence.path
  unless (← git #["hash-object", "--no-filters", "--", evidence.path]) == evidence.hash do
    throw (IO.userError "stale evidence digest")

def verifyScope (grant : DelegationGrant) (usage : DelegationUse) : IO Unit := do
  let some evidence := usage.evidence.head? | throw (IO.userError "scope review required")
  let review : DelegationScopeReview ← readJson evidence.path
  unless review.contractHash == usage.contractHash && review.target == usage.target &&
      review.criterion == usage.criterion && review.contentHash == usage.contentHash &&
      review.verdict && nonempty review.findings && nonempty review.reviewedBy &&
      review.reviewedBy != usage.agent && review.reviewedBy != grant.authorizedBy do
    throw (IO.userError "fresh independent scope review required")

def verifyCompletion (contract : DelegationContract) (usage : DelegationUse)
    (evidence : DelegationEvidence) : IO DelegationCompletion := do
  let receipt : DelegationCompletion ← readJson evidence.path
  unless receipt.contractHash == usage.contractHash &&
      (receipt.acceptance.map (·.criterion)).mergeSort (· ≤ ·) == contract.criteria.mergeSort (· ≤ ·) do
    throw (IO.userError "all frozen acceptance criteria require evidence")
  verifyEvidence receipt.report
  for acceptance in receipt.acceptance do verifyEvidence acceptance.evidence
  let report : Json ← readJson receipt.report.path
  let .ok "PASS" := report.getObjVal? "overall" >>= Json.getStr? |
    throw (IO.userError "PASS verification report required")
  return receipt

def validateAll (registry : Registry) : IO Unit := do
  if !(← ledgerPath.pathExists) && !registry.approvals.any
      (fun r => r.approval.authority != .human) then
    let repository ← IO.Process.output { cmd := "git", args := #["rev-parse", "--git-dir"] }
    if repository.exitCode != 0 then return
    let history ← IO.Process.output { cmd := "git", args := #["log", "--format=%H", "--", ledgerPath.toString] }
    if history.stdout.trimAscii.toString.isEmpty then return
  let ledger ← loadLedger
  verifyLedgerHistory ledger false
  let mut previous := []
  for usage in ledger do
    let grant ← loadGrant usage.contract
    unless usage.contractHash == grant.confirmedHash do throw (IO.userError "stale grant reference")
    match validateDelegationUse grant.contract previous usage with
    | .error error => throw (IO.userError error)
    | .ok _ => pure ()
    verifyAnchors registry grant.contract
    for evidence in usage.evidence do verifyEvidence evidence
    if usage.decision == "approve" then
      verifyScope grant usage
      let some scope := usage.evidence.head? | throw (IO.userError "scope receipt missing")
      let review : DelegationScopeReview ← readJson scope.path
      unless previous.any (fun u => u.decision == "review" && u.target == usage.target &&
          u.contentHash == usage.contentHash && u.agent == review.reviewedBy) do
        throw (IO.userError "scope reviewer must match consumed review reservation")
      if usage.requiresCompletion then
        let some evidence := usage.evidence[1]? | throw (IO.userError "G1/G3 approval requires completion evidence")
        discard <| verifyCompletion grant.contract usage evidence
    if usage.decision == "complete" then
      let some evidence := usage.evidence.head? | throw (IO.userError "completion evidence required")
      discard <| verifyCompletion grant.contract usage evidence
    previous := previous ++ [usage]
  for record in registry.approvals do
    match record.approval.authority with
    | .human => pure ()
    | .delegated contract hash sequence =>
      unless ledger.any (fun usage => usage.sequence == sequence && usage.contract == contract &&
          usage.contractHash == hash && usage.decision == "approve" &&
          usage.agent == record.approval.approvedBy && usage.target == record.target.render &&
          usage.contentHash == renderHash record.approval.contentHash &&
          usage.date == record.approval.date && usage.note == record.approval.note) do
        throw (IO.userError "delegated approval lacks authorized ledger use")

def runGrant (registry : Registry) (args : List String) : IO UInt32 := do
  try
    match args with
    | ["inspect", path] =>
      let contract : DelegationContract ← readJson path
      match validateDelegationContract contract with
      | .error error => throw (IO.userError error)
      | .ok _ => pure ()
      IO.println (delegationContractHash contract)
      return 0
    | ["grant", path, "--by", human, "--note", note, "--date", date, "--confirm-hash", hash] =>
      let contract : DelegationContract ← readJson path
      match validateDelegationContract contract with
      | .error error => throw (IO.userError error)
      | .ok _ => pure ()
      unless hash == delegationContractHash contract && nonempty human && nonempty note &&
          nonempty date && !contract.agents.contains human do
        throw (IO.userError "explicit human confirmation of exact contract hash required")
      verifyAnchors registry contract
      let history ← git #["log", "--format=%H", "--", ".delegation/contracts"]
      let existing := (".delegation/contracts" : System.FilePath)
      unless history.isEmpty && !(← existing.pathExists) do
        throw (IO.userError "one contract per repository; replacement/budget reset forbidden")
      let grant : DelegationGrant := { contract, authorizedBy := human, date, note, confirmedHash := hash }
      IO.FS.createDirAll existing
      IO.FS.writeFile (grantPath contract.identifier) ((toJson grant).pretty ++ "\n")
      IO.println "grant recorded; commit before delegated use (human identity is an operator assertion)"
      return 0
    | _ =>
      IO.eprintln "usage: idchain delegation inspect <contract.json> | grant <contract.json> --by <human> --note <note> --date <date> --confirm-hash <hash> | use <request.json>"
      return 2
  catch error =>
    IO.eprintln s!"idchain delegation: {error}"
    return 1

end Delegation
end Idchain
