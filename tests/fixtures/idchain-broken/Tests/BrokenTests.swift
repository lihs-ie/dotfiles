import Testing

// idchain fixture (負例): TC-048-1 はコードには存在するが xunit 実行結果に含まれない
// (未実行 TC の負例)。コンパイル対象ではなく走査対象になるだけの fixture。

@Test("TC-048-1: 未承認仕様のテスト")
func unapprovedSpecTest() {}
