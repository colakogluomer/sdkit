# Next.js idioms

Language- and framework-level rules for any Next.js + React repo. Project architecture (folder layout, data layer, auth,
design system) belongs in the project's own rules, not here.

## Server and client components

- Components are server components by default. Add `'use client'` only where state, effects, event handlers or browser APIs are needed.
- Push the client boundary down: extract the small interactive part into its own client component instead of marking a whole page or tree.
- Client components cannot import server-only code; keep data access in modules that never reach the client bundle.
- Props crossing the boundary must be serialisable (no functions, class instances).

## Data fetching

- Fetch on the server (server components, route handlers, server actions), close to where the data is used.
- Do not fetch in `useEffect` or derive state in an effect. Compute derived values during render; use `useMemo` only for measured cost.
- Set caching and revalidation explicitly where it matters (`revalidate`, `cache: 'no-store'`); do not rely on defaults you have not checked.
- Handle loading and error states with `loading.tsx` / `error.tsx` or Suspense boundaries.

## Secrets and environment

- Anything in a `NEXT_PUBLIC_*` variable ships to the browser. Never put a secret, token, password or private key there.
- Read secrets only in server code. Read env through one typed module, not `process.env.X` scattered across files.
- Document every variable in `.env.example`.

## Route handlers and server actions

- Treat all input as untrusted: validate body, query and params with a schema (for example zod) before use.
- Return explicit status codes and a consistent error shape; never leak stack traces or internal errors.
- Check authentication and authorisation inside each handler or action, not only in middleware.

## TypeScript and React

- No `any`. Use `unknown` and narrow, or write the type. Prefer inferred types from schemas.
- Stable, unique `key` props from data ids; never the array index for lists that reorder or change.
- No `dangerouslySetInnerHTML` with unsanitised content.
- Keep components small; extract hooks for reusable stateful logic.

## Images, links, accessibility

- Use `next/image` for images (with `width`/`height` or `fill`, and meaningful `alt`) and `next/link` for internal navigation.
- Use semantic elements (`button`, `nav`, `main`, headings in order); interactive elements must be keyboard reachable.
- Every form control has a label; icon-only buttons have an accessible name.
- Do not rely on colour alone to convey state.
