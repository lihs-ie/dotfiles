/-!
# FNV-1a 64bit ハッシュ

承認のコンテンツ束縛用の決定論的指紋 (セキュリティ目的ではない。真正性は git 履歴が担保)。
Lean バージョンに依存しない自前実装で、ハッシュ値の長期安定性を保証する。
-/

namespace Idchain

def fnv1aOffsetBasis : UInt64 := 14695981039346656037
def fnv1aPrime : UInt64 := 1099511628211

def fnv1a (bytes : ByteArray) : UInt64 :=
  bytes.foldl (fun h b => (h ^^^ (UInt64.ofNat b.toNat)) * fnv1aPrime) fnv1aOffsetBasis

def hashString (s : String) : UInt64 :=
  fnv1a s.toUTF8

/-- ハッシュ値の 16 進表記 (16 桁ゼロ埋め小文字。レポート・Approvals.lean 生成用)。 -/
def renderHash (h : UInt64) : String :=
  let s := String.ofList (Nat.toDigits 16 h.toNat)
  String.ofList (List.replicate (16 - s.length) '0') ++ s

end Idchain
