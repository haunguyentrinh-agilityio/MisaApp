# Frontend guidance

- React 19 + TypeScript (strict, `verbatimModuleSyntax`, `erasableSyntaxOnly`: no enums, no parameter properties). Package manager is **pnpm**; Node >= 24.
- **Structure**: `src/features/<feature>/` holds the component(s), `<feature>Api.ts` (typed calls + DTO types), CSS, and `*.test.tsx`. Shared helpers in `src/lib/` (`apiRequest`, `ApiError`).
- **API calls** go through `apiRequest<T>()`; always relative `/api/...` URLs (Vite proxies in dev, nginx in Docker). Keep DTO types in sync with the backend records.
- **Styling**: plain CSS per component with BEM-ish class names (`chat__message--user`) and the CSS variables in `src/index.css`. Support light and dark.
- **Accessibility first**: label every control, use roles (`log`, `alert`) for live content. Tests query by role/label, not class names.
- **Unit tests**: Vitest + React Testing Library + user-event. Mock the network with `vi.stubGlobal('fetch', ...)`; `src/test/setup.ts` resets mocks and `localStorage` after each test.
- **E2E**: `e2e/` is a separate pnpm package (`@playwright/test`). The Docker image tag in `e2e/Dockerfile` must match the `@playwright/test` version. Don't assert on LLM wording; assert on structure.
- Before finishing: `pnpm lint && pnpm typecheck && pnpm test && pnpm build`.
