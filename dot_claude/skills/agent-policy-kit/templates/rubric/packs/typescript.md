# rubric pack: TypeScript (Node.js / tRPC / NestJS)

## 追加判定項目
- 新規 `router` / `controller` が App の Composition Root (NestJS `AppModule` / Express `app.use` / tRPC `appRouter`) で登録されている。
- `any` / `@ts-ignore` が本番コードに追加されていない (型安全性の劣化)。
- `process.env` 直読みが domain / use-case 層に漏れていない (config injection)。
- Jest `jest.mock()` / `jest.spyOn()` が本番ファイル (`.ts` / `.tsx` で `test/` 外) に混入していない。

## seed / clock / random の非決定性制御
- `Date.now()` / `Math.random()` / `crypto.randomUUID()` を直接本番コードで呼ばず、DI 可能な `Clock` / `IdGenerator` interface に差し替える。
- `jest.useFakeTimers()` + `jest.setSystemTime()` でタイムスタンプを固定し、決定論テストを保証する。
- `jest.spyOn(Math, 'random').mockReturnValue(0.5)` でランダム性をシード固定する。

## 推奨証拠
- `pnpm test --run` (vitest) / `jest --runInBand` で全テスト pass。
- `pnpm tsc --noEmit` で型エラー 0。
- `pnpm lint` (ESLint + `@typescript-eslint`) でルール違反 0。
