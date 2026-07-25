import Idchain.Checks

/-!
# 人間向けビュー生成 (U9)

正本 (Lean) から人間が読む文書を生成する。**生成物は編集禁止** — 正本を変更して再生成する。
鮮度検査 (`views --check`) は再生成内容とディスクの一致を機械判定する。
-/

namespace Idchain

def viewHeader : String :=
  "<!-- idchain: DO NOT EDIT — この文書は Lean 正本から自動生成される (lake exe idchain views で再生成) -->\n\n"

inductive ApprovalStatus where
  | approved (record : ApprovalRecord)
  | stale (record : ApprovalRecord)
  | unapproved
  deriving Inhabited

def Registry.approvalStatus (registry : Registry) (identifier : SimpleIdentifier) : ApprovalStatus :=
  match registry.approvals.find? (·.target == identifier) with
  | none => .unapproved
  | some record =>
    match registry.contentHashFor identifier with
    | some currentHash =>
      if record.approval.contentHash == currentHash then .approved record else .stale record
    | none => .stale record

def approvalStatusLine : ApprovalStatus → String
  | .approved record => s!"承認済 ({record.approval.approvedBy}, {record.approval.date})"
  | .stale _ => "承認失効 (内容変更により再承認が必要)"
  | .unapproved => "未承認"

def joinLines (items : List String) : String :=
  String.intercalate "\n" items ++ "\n"

def renderEvidence : Evidence → String
  | .pending topic => s!"要証拠: {topic}（空欄 — 埋まるまでゲートを通さない）"
  | .recorded topic source => s!"{topic} — {source}"

def hypothesisStatusLabel : HypothesisStatus → String
  | .untested => "未検証"
  | .supported => "支持"
  | .refuted => "反証"

def renderWhyWhat (registry : Registry) : String :=
  let problems := registry.problems.flatMap fun problem =>
    [s!"### {SimpleIdentifier.render ⟨.pb, problem.number⟩}: {problem.statement}", ""]
    ++ problem.evidence.map (fun evidence => s!"- 根拠: {renderEvidence evidence}") ++ [""]
  let values := registry.values.flatMap fun value =>
    [s!"### {SimpleIdentifier.render ⟨.vl, value.number⟩}: {value.statement}", "",
     s!"- 対応課題: {SimpleIdentifier.render ⟨.pb, value.problem⟩}",
     s!"- 合格ライン: {value.successCriterion}", ""]
  let featureAreas := registry.featureAreas.flatMap fun featureArea =>
    [s!"### {SimpleIdentifier.render ⟨.fa, featureArea.number⟩}: {featureArea.name}", ""]
    ++ featureArea.values.map
      (fun number => s!"- 対応価値: {SimpleIdentifier.render ⟨.vl, number⟩}") ++ [""]
  let hypotheses := registry.hypotheses.flatMap fun hypothesis =>
    [s!"### {SimpleIdentifier.render ⟨.hy, hypothesis.number⟩}: {hypothesis.statement}", "",
     s!"- 指標 / 閾値: {hypothesis.metric} / {hypothesis.threshold}",
     s!"- 重要度 {hypothesis.importance} × 証拠の強さ {hypothesis.evidenceStrength}",
     s!"- 関連課題: {String.intercalate "、" (hypothesis.problems.map fun number => SimpleIdentifier.render ⟨.pb, number⟩)}",
     s!"- 状態: {hypothesisStatusLabel hypothesis.status}", ""]
  let trace := registry.featureAreas.flatMap fun featureArea =>
    featureArea.values.flatMap fun valueNumber =>
      match registry.findValue valueNumber with
      | none => []
      | some value =>
        [s!"- {SimpleIdentifier.render ⟨.pb, value.problem⟩} ⇔ {SimpleIdentifier.render ⟨.vl, value.number⟩} ⇔ {SimpleIdentifier.render ⟨.fa, featureArea.number⟩}"]
  viewHeader ++ joinLines (
    ["# Why/What ドキュメント", "", "## 顧客課題 (PB)", ""] ++ problems ++
    ["## 提供価値 (VL)", ""] ++ values ++
    ["## 機能領域 (FA)", ""] ++ featureAreas ++
    ["## 仮説 (HY)", ""] ++ hypotheses ++
    ["## Traceability", ""] ++ trace)

def renderSpecification (registry : Registry) : String :=
  let sections := registry.featureAreas.flatMap fun featureArea =>
    let specsOfArea := registry.specs.filter (·.featureArea == featureArea.number)
    [s!"## {SimpleIdentifier.render ⟨.fa, featureArea.number⟩}: {featureArea.name}", ""] ++
    specsOfArea.flatMap fun spec =>
      let identifier : SimpleIdentifier := ⟨.sp, spec.number⟩
      let status := registry.approvalStatus identifier
      let noteLines := match status with
        | .approved record => [s!"- 判断根拠: {record.approval.note}"]
        | _ => []
      let testCases := registry.testCases.filter (·.identifier.spec == spec.number)
      let testCaseLine :=
        if testCases.isEmpty then "- テストケース: なし"
        else s!"- テストケース: {String.intercalate "、" (testCases.map (·.identifier.render))}"
      [s!"### {identifier.render}: {spec.text}", "",
       s!"- 状態: {approvalStatusLine status}"] ++ noteLines ++ [testCaseLine, ""]
  viewHeader ++ joinLines (["# 仕様書", ""] ++ sections)

def renderTestDesign (registry : Registry) : String :=
  let sections := registry.specs.flatMap fun spec =>
    let testCases := registry.testCases.filter (·.identifier.spec == spec.number)
    [s!"## {SimpleIdentifier.render ⟨.sp, spec.number⟩}: {spec.text}", ""] ++
    testCases.map (fun testCase =>
      s!"- {testCase.identifier.render} ({testCase.kind.canonicalString}): {testCase.description}")
    ++ [""]
  viewHeader ++ joinLines (
    ["# テスト設計書", "",
     "各 TC は仕様 (SP) から導出される。実装からの導出は禁止 (実装追認テストを防ぐ)。", ""]
    ++ sections)

def renderLedger (registry : Registry) : String :=
  let rows := registry.learnings.map fun learning =>
    let hypothesis := match learning.hypothesis with
      | some number => SimpleIdentifier.render ⟨.hy, number⟩
      | none => "—"
    s!"| {SimpleIdentifier.render ⟨.ll, learning.number⟩} | {learning.date} | {hypothesis} | {learning.outcome} |"
  viewHeader ++ joinLines (
    ["# 学び台帳", "", "外れた仮説も消さずに記録する (append-only)。", "",
     "| ID | 日付 | 関連仮説 | 学び |", "|---|---|---|---|"] ++ rows)

def roadmapStatusLabel : RoadmapItemStatus → String
  | .planned => "計画中"
  | .inCycle => "着手中"
  | .done => "完了"
  | .dropped => "見送り"

/-- RM を priority 昇順で表示する (dropped も削除禁止のため一覧に残る)。 -/
def renderRoadmap (registry : Registry) : String :=
  let sorted := registry.roadmapItems.mergeSort (fun a b => a.priority ≤ b.priority)
  let rows := sorted.map fun item =>
    let hypothesis := match item.hypothesis with
      | some number => SimpleIdentifier.render ⟨.hy, number⟩
      | none => "—"
    s!"| {SimpleIdentifier.render ⟨.rm, item.number⟩} | {item.title} | {roadmapStatusLabel item.status} | {item.priority} | {hypothesis} | {item.source} |"
  viewHeader ++ joinLines (
    ["# ロードマップ", "", "優先度 (priority) が小さいほど次に潰す順。dropped も削除せず残す (意思の痕跡)。", "",
     "| ID | 題名 | 状態 | 優先度 | 関連HY | 出典 |", "|---|---|---|---|---|---|"] ++ rows)

/-- 生成対象の全ビュー (ファイル名 × 内容)。 -/
def views (registry : Registry) : List (String × String) := [
  ("why-what.md", renderWhyWhat registry),
  ("specification.md", renderSpecification registry),
  ("test-design.md", renderTestDesign registry),
  ("ledger.md", renderLedger registry),
  ("roadmap.md", renderRoadmap registry)
]

end Idchain
