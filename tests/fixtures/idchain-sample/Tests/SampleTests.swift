import Testing

// idchain fixture: TC ID 注釈規約のサンプル。実装は鎖の外 (発表 p.36)。
// テスト実行結果は results/latest-tests.xml で模擬する (決定論的 fixture)。

@Test("TC-047-1: 明細3件で小計一致")
func subtotalMatchesThreeItems() {}

@Test("TC-047-2: 明細0件で小計0")
func subtotalZeroItems() {}
