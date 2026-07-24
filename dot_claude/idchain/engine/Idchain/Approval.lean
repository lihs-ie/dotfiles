import Idchain.Canonical

/-!
# 承認 (人間ゲート G1/G2/G3)

承認は内容の正準直列化ハッシュに束縛され、承認後の内容変更で自動失効する。
「意思の痕跡」(判断根拠・棄却案) は note として正本の一部になる (発表 p.69:
記録あり＝有効、記録なし＝不完全)。書込は approve コマンド経由のみ、真正性は git 履歴で担保。
-/

namespace Idchain

structure Approval where
  approvedBy : String
  date : String
  note : String
  contentHash : UInt64
  deriving Repr, DecidableEq, Inhabited

structure ApprovalRecord where
  target : SimpleIdentifier
  approval : Approval
  deriving Repr, DecidableEq, Inhabited

/-- 承認が現内容に対して有効か (ハッシュ束縛検査)。 -/
def Approval.isFresh [Canonical α] (approval : Approval) (content : α) : Bool :=
  approval.contentHash == contentHashOf content

/-- 現内容から承認を作成する (approve コマンドの中核)。 -/
def approvalFor [Canonical α] (approvedBy date note : String) (content : α) : Approval :=
  { approvedBy, date, note, contentHash := contentHashOf content }

end Idchain
