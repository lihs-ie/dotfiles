# rubric pack: Java (Spring Boot)

## 追加判定項目
- 新規 `@RestController` / `@Service` / `@Repository` が Spring DI コンテナに登録され (`@Component` / `@Bean`)、`ApplicationContext` から到達できる。
- `@Transactional` が service 層にのみ付与され、repository 層への直接 rollback 依存が無い。
- 新規 endpoint が `SecurityFilterChain` の適切な permit/authenticate ルールに追加されている。
- `@MockBean` / `@SpyBean` は `@SpringBootTest` のみで使い、本番 config に混入しない。

## seed / clock / random の非決定性制御
- `LocalDateTime.now()` / `UUID.randomUUID()` を本番コードで直接呼ばず、`Clock` bean / `IdGenerator` インターフェースに差し替える。
- テストでは `@TestConfiguration` で fixed `Clock` を inject し、決定論的結果を保証する。
- `@Sql` アノテーション / `Testcontainers` で DB シードを固定し、テスト間の状態汚染を防ぐ。

## 推奨証拠
- `./mvnw test` または `./gradlew test` (Surefire / Jacoco レポート)。
- `@SpringBootTest` + `MockMvc` / `WebTestClient` で endpoint を実際に叩く integration test。
- Actuator `/actuator/health` が起動後に `UP` を返すことを smoke test で確認。
