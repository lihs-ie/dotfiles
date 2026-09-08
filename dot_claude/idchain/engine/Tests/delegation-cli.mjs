// Production CLI journey in an isolated Git repository. No external services.
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve, dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const engine = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixture = mkdtempSync(join(tmpdir(), 'idchain-delegation-'));
const lean = process.env.IDCHAIN_LEAN || `${process.env.HOME}/.elan/bin/lean`;
const env = {...process.env, LEAN_PATH: `${engine}/.lake/build/lib/lean:${fixture}`};
const write = (path, value) => {
  mkdirSync(dirname(join(fixture, path)), {recursive:true});
  writeFileSync(join(fixture, path), typeof value === 'string' ? value : JSON.stringify(value,null,2));
};
const read = path => readFileSync(join(fixture,path),'utf8');
function command(cmd, args, expected = 0) {
  const result = spawnSync(cmd,args,{cwd:fixture,env,encoding:'utf8'});
  assert.equal(result.status, expected, `${cmd} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}
const git = (...args) => command('git',args);
const commit = note => {git('add','.'); git('commit','-qm',note);};
const digest = path => git('hash-object','--no-filters','--',path);
const evidence = path => ({path, hash:digest(path)});
function cli(args, expected=0) {
  command(lean,['-o','Canon/Approvals.olean','Canon/Approvals.lean']);
  command(lean,['-o','Canon/SemanticReviews.olean','Canon/SemanticReviews.lean']);
  return command(lean,['--run','Fixture.lean',...args],expected);
}
const outputs = () => ['.delegation/ledger.json','Canon/Approvals.lean'].map(path=>
  existsSync(join(fixture,path)) ? read(path) : null);
let count = 0;
const nextSequence = () => existsSync(join(fixture,'.delegation/ledger.json')) ? JSON.parse(read('.delegation/ledger.json')).length+1 : 1;
function use(request, note) {
  write('request.json',{...request,sequence:nextSequence()});
  cli(['delegation','use','request.json']); commit(note);
}
function rejected(name, request) {
  const before = outputs(); write('request.json',{...request,sequence:nextSequence()});
  cli(['delegation','use','request.json'],1);
  assert.deepEqual(outputs(),before,`${name}: rejected operation wrote state`);
  console.log(`PASS ${name}`); count++;
}

write('lean-toolchain',readFileSync(join(engine,'lean-toolchain'),'utf8'));
write('.gitignore','*.olean\n*.ilean\n.gate-status.json\nrequest.json\n');
write('Canon/Approvals.lean','import Idchain\nnamespace Canon\ndef approvals : List Idchain.ApprovalRecord := []\nend Canon\n');
write('Canon/SemanticReviews.lean','import Idchain\nnamespace Canon\ndef semanticReviews : List Idchain.SemanticReview := []\nend Canon\n');
write('Fixture.lean',`import Idchain.Cli
import Canon.Approvals
import Canon.SemanticReviews
open Idchain
def problem : Problem := ⟨1, "observable result", []⟩
def spec : Spec := ⟨1, "addition yields four", 1⟩
def learning : Learning := ⟨1, "2026-09-08", none, "addition result verified"⟩
def hypothesis : Hypothesis := ⟨1, "result hypothesis", "result", "four", 1, 1, [1], .untested⟩
def roadmap : RoadmapItem := ⟨1, "bounded delivery", .planned, 1, some 1, "discovery"⟩
def priorHypothesis : Hypothesis := ⟨1, "result hypothesis", "result", "four", 1, 1, [1], .untested⟩
def priorRoadmap : RoadmapItem := ⟨1, "bounded delivery", .planned, 1, some 1, "discovery"⟩
def registry : Registry := { Registry.empty with
  problems := [problem], values := [⟨1, "result", 1, "four"⟩],
  featureAreas := [⟨1, "arithmetic", [1]⟩], specs := [spec],
  testCases := [],
  learnings := [learning],
  hypotheses := [hypothesis], roadmapItems := [roadmap],
  approvals := ([(⟨⟨.pb, 1⟩, approvalFor "human" "2026-09-08" "frozen outcome" problem⟩ : ApprovalRecord),
    ⟨⟨.hy, 1⟩, approvalFor "human" "2026-09-08" "G1 hypothesis" priorHypothesis⟩,
    ⟨⟨.rm, 1⟩, approvalFor "human" "2026-09-08" "G1 roadmap" priorRoadmap⟩].filter
    (fun r => !Canon.approvals.any (·.target == r.target))) ++ Canon.approvals,
  semanticReviews := Canon.semanticReviews }
def main (args : List String) : IO UInt32 := do
  if args == ["hashes"] then
    IO.println (renderHash (contentHashOf problem))
    IO.println (renderHash (contentHashOf spec))
    IO.println (renderHash (contentHashOf learning))
    IO.println (renderHash (contentHashOf hypothesis))
    IO.println (renderHash (contentHashOf roadmap))
    return 0
  Idchain.Cli.run registry args
`);
write('idchain.json',{repoRoot:'.',testFileRoots:['tests'],testFileExtensions:['.js'],xunitPath:'results.xml'});
git('init','-q'); git('config','user.name','Fixture Operator'); git('config','user.email','fixture@example.invalid');
command(join(engine,'.lake/build/bin/idchain-dev'),['check']);
console.log('PASS human mode in unborn Git repository');
commit('fixture baseline');
const [anchorHash,contentHash,learningHash] = cli(['hashes']).split('\n');
const contract = {identifier:'delivery',outcome:'addition externally observed',criteria:['four'],
  nonGoals:['unrelated arithmetic'],targets:['SP-001','LL-001','HY-001','RM-001'].map(target=>({target,criterion:'four'})),
  anchors:[{target:'PB-001',hash:anchorHash}],agents:['codex','reviewer'],
  decisions:['prepare','review','approve','complete'],preparationBudget:4,reviewBudget:5,decisionBudget:6,
  stopConditions:['scope delta','budget exhaustion','failed evidence']};
write('contract.json',contract);
const hash = cli(['delegation','inspect','contract.json']);
cli(['delegation','grant','contract.json','--by','human','--note','explicit authorization','--date','2026-09-08','--confirm-hash',hash]);
const base = {sequence:1,contract:'delivery',contractHash:hash,agent:'codex',decision:'prepare',
  target:'SP-001',criterion:'four',date:'2026-09-08',note:'bounded action',contentHash:'',requiresCompletion:false,evidence:[]};
rejected('uncommitted grant cannot authorize',base);
commit('human grant');
rejected('missing grant',{...base,contract:'missing'});
rejected('stale grant hash',{...base,contractHash:'stale'});
rejected('out-of-scope target',{...base,target:'SP-002'});
rejected('criterion reassignment',{...base,criterion:'other'});
rejected('human impersonation',{...base,agent:'human'});
write('request.json',base); cli(['delegation','use','request.json']);
rejected('uncommitted previous use',{...base,sequence:2});
commit('preparation reservation');
write('request.json',{...base,sequence:2,target:'LL-001'}); cli(['delegation','use','request.json']); commit('learning preparation reservation');
const review = {...base,sequence:3,agent:'reviewer',decision:'review',contentHash};
write('request.json',review); cli(['delegation','use','request.json']); commit('review reservation');
write('request.json',{...review,sequence:4,target:'LL-001',contentHash:learningHash}); cli(['delegation','use','request.json']); commit('learning review reservation');
write('scope.json',{contractHash:hash,target:'SP-001',criterion:'four',contentHash,
  reviewedBy:'reviewer',verdict:true,findings:'within frozen outcome and non-goals'});
commit('independent scope review');
const approve = {...base,sequence:5,decision:'approve',contentHash,evidence:[evidence('scope.json')]};
rejected('G2 requires semantic review',approve);
cli(['semantic-review','SP-001','--by','reviewer','--date','2026-09-08','--verdict','pass','--findings','precise behavior']);
commit('semantic review');
const beforeFirstApproval = read('Fixture.lean');
write('Fixture.lean',beforeFirstApproval.replace('testCases := [],','testCases := [⟨⟨1, 1⟩, "too early", .example⟩],'));
rejected('TC derivation before first G2 remains forbidden',approve); write('Fixture.lean',beforeFirstApproval);
write('request.json',approve); cli(['delegation','use','request.json']); commit('delegated G2 approval');
assert.match(read('Canon/Approvals.lean'),/authority := \.delegated "delivery"/);
assert.match(read('Canon/Approvals.lean'),/approvedBy := "codex"/);
write('Fixture.lean',read('Fixture.lean').replace('testCases := [],','testCases := [⟨⟨1, 1⟩, "addition equals four", .example⟩],'));
write('tests/arithmetic.js','// TC-001-1: actual acceptance\nif (2+2 !== 4) throw Error("addition");\n');
command(process.execPath,['tests/arithmetic.js']);
write('results.xml','<testsuites><testsuite><testcase name="TC-001-1: actual acceptance"/></testsuite></testsuites>');
write('acceptance.txt','2 + 2 = 4; executed tests/arithmetic.js successfully\n');
commit('TC derived after G2 and executed');
write('Fixture.lean',read('Fixture.lean').replace('addition yields four','addition of two and two yields four'));
const revisedHash = cli(['hashes']).split('\n')[1];
use({...review,contentHash:revisedHash},'revision independent review reservation');
cli(['semantic-review','SP-001','--by','reviewer','--date','2026-09-08','--verdict','pass','--findings','same bounded behavior, wording clarified']);
write('revision-scope.json',{contractHash:hash,target:'SP-001',criterion:'four',contentHash:revisedHash,
  reviewedBy:'reviewer',verdict:true,findings:'same authorized outcome'}); commit('fresh revision reviews');
use({...approve,contentHash:revisedHash,evidence:[evidence('revision-scope.json')]},'reapprove revised SP retaining existing TC');
console.log('PASS stale SP reapproval retains derived TC');
cli(['check']); cli(['report','--date','2026-09-08']); commit('engine report');
write('completion.json',{contractHash:hash,report:evidence('reports/2026-09-08/verification-report.json'),
  acceptance:[{criterion:'four',evidence:evidence('acceptance.txt')}]});
commit('acceptance receipt');
write('learning-scope.json',{contractHash:hash,target:'LL-001',criterion:'four',contentHash:learningHash,
  reviewedBy:'reviewer',verdict:true,findings:'observed learning matches acceptance'}); commit('learning scope receipt');
const learningApproval = {...approve,sequence:6,target:'LL-001',contentHash:learningHash,requiresCompletion:true,
  evidence:[evidence('learning-scope.json')]};
rejected('G3 learning needs completion evidence',learningApproval);
rejected('G3 cannot claim preparation classification',{...learningApproval,requiresCompletion:false});
use({...learningApproval,evidence:[...learningApproval.evidence,evidence('completion.json')]},'delegated G3 learning with real evidence');
for (const [target, definition, fromStatus, toStatus, hashIndex] of [
  ['HY-001','def hypothesis : Hypothesis', '.untested','.supported',3],
  ['RM-001','def roadmap : RoadmapItem', '.planned','.done',4]]) {
  write('Fixture.lean',read('Fixture.lean').split('\n').map(line=>line.startsWith(definition) ? line.replace(fromStatus,toStatus) : line).join('\n'));
  const updatedHash = cli(['hashes']).split('\n')[hashIndex];
  use({...base,target},`${target} preparation reservation`);
  use({...review,target,contentHash:updatedHash},`${target} review reservation`);
  write(`${target}-scope.json`,{contractHash:hash,target,criterion:'four',contentHash:updatedHash,
    reviewedBy:'reviewer',verdict:true,findings:'status follows actual acceptance evidence'}); commit(`${target} fresh scope review`);
  const decision = {...approve,target,contentHash:updatedHash,requiresCompletion:true,
    evidence:[evidence(`${target}-scope.json`),evidence('completion.json')]};
  if (target === 'HY-001') {
    const unchanged = read('Fixture.lean');
    write('Fixture.lean',unchanged.split('\n').map(line=>line.startsWith('def roadmap :') ? line.replace('.planned','.done') : line).join('\n'));
    rejected('prospective G3 preserves other target stale approval',decision); write('Fixture.lean',unchanged);
    const passing = read('results.xml');
    write('results.xml',passing.replace('/>','><failure message="regression"/></testcase>'));
    rejected('prospective G3 preserves real test failure',decision); write('results.xml',passing);
  }
  use(decision,`${target} evidence-backed G3 transition`);
  cli(['check']); cli(['report','--date','2026-09-08']);
  console.log(`PASS ${target} G1-approved status transition through G3`);
}
rejected('cumulative preparation budget',base);
rejected('cumulative review budget',review);
const complete = {...base,sequence:nextSequence(),decision:'complete',evidence:[evidence('completion.json')]};
rejected('completion without evidence',{...complete,evidence:[]});
write('minimal-report.json',{overall:'PASS'}); commit('invalid report fixture');
write('invalid-completion.json',{contractHash:hash,report:evidence('minimal-report.json'),
  acceptance:[{criterion:'four',evidence:evidence('acceptance.txt')}]}); commit('invalid completion fixture');
rejected('self-asserted PASS is not engine evidence',{...complete,evidence:[evidence('invalid-completion.json')]});
const otherReport = JSON.parse(read('reports/2026-09-08/verification-report.json'));
otherReport.specs[0].id = 'SP-999';
write('other-report.json',otherReport); commit('other target report fixture');
write('other-completion.json',{contractHash:hash,report:evidence('other-report.json'),
  acceptance:[{criterion:'four',evidence:evidence('acceptance.txt')}]}); commit('other target receipt fixture');
rejected('other target report is stale',{...complete,evidence:[evidence('other-completion.json')]});
const grantPath = '.delegation/contracts/delivery.json';
const originalGrant = read(grantPath);
write(grantPath,originalGrant.replace('addition externally observed','mutated outcome'));
rejected('mutated grant',complete); write(grantPath,originalGrant);
const originalLedger = read('.delegation/ledger.json');
write('.delegation/ledger.json',[]); rejected('ledger reset',complete); write('.delegation/ledger.json',originalLedger);
const originalFixture = read('Fixture.lean');
write('Fixture.lean',originalFixture.replace('observable result','changed outcome'));
rejected('stale upstream anchor',complete); write('Fixture.lean',originalFixture);
write('request.json',complete); cli(['delegation','use','request.json']); commit('completed bounded outcome');
cli(['check']); cli(['report','--date','2026-09-08']);
rejected('completed contract cannot reopen',{...base,sequence:8});
write('contract-new.json',{...contract,identifier:'renamed'});
const newHash = cli(['delegation','inspect','contract-new.json']);
cli(['delegation','grant','contract-new.json','--by','human','--note','reset attempt','--date','2026-09-08','--confirm-hash',newHash],1);
console.log('PASS contract rename cannot reset budget'); count++;
write('.delegation/ledger.json',[]); commit('invalid committed ledger reset');
cli(['check'],1); console.log('PASS committed ledger reset rejected'); count++;
console.log(`${count} negative cases and grant -> reservations -> G2 -> TC -> check/report -> completion passed`);
console.log(`fixture artifact: ${fixture}`);
