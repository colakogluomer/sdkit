# React testing

Style rules for React / Next.js tests. Test runner, file layout and shared fixtures are project facts; see `project.md`
("Test layout") and the project's own rules.

## Naming

Pattern: `describe('Subject')` + `it('does X when condition')`, or `test('subject: condition -> result')`.

```ts
describe('OrderForm', () => {
  it('shows a validation error when the quantity is zero', ...)
  it('disables submit while the request is pending', ...)
})
```

## Component tests (React Testing Library)

- Test what the user sees and does: query by role, label or text (`getByRole`, `getByLabelText`); use `userEvent`, not `fireEvent`.
- Do not assert on implementation details: component state, hook internals, CSS class names, child component props, call order.
- `data-testid` is a last resort when no accessible query works.
- Prefer `findBy*` / `waitFor` over fixed timeouts.
- Snapshots only for small, stable output (a serialised value), never whole component trees.

## Network

- Mock the network boundary with MSW, not by mocking `fetch` or your own API client modules.
- Default handlers return the happy path; each test overrides for errors and edge cases.
- Fail on unhandled requests.

## Isolation

- Each test renders its own tree and builds its own data; no shared mutable state, no order dependence.
- Reset handlers, timers and mocks after each test.
- Server components and route handlers: test the logic as plain functions with their dependencies passed in; render client components in jsdom.

## What to test

- Priority: business rules, validation and error states, conditional rendering, accessibility of interactive parts.
- Do not test the framework or third-party libraries.
- End-to-end tests (Playwright/Cypress) only for critical flows (sign-in, checkout, core create/edit path), kept few and stable.
