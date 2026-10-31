# React Native testing

Style rules for tests in a React Native app. Where tests live and which flows are critical are project facts; see
`project.md`.

## Component tests

- Use React Native Testing Library and test what the user sees and does: query with `getByRole`, `getByText`,
  `getByLabelText`; avoid `testID` unless nothing else identifies the element.
- Drive interaction with `userEvent` (or `fireEvent` when needed) and assert on visible results, not on state or props.
- Use `findBy*` / `waitFor` for async UI; never sleep.
- Use fake timers for debounce, timeouts and animations, and restore real timers after.

## Mocks

- Mock native modules in one place (the jest setup file), with sensible defaults; a test overrides only what it needs.
- Mock at the boundary (network, storage, permissions, navigation), not your own components.
- Each test builds its own state; tests never share mutable state or depend on order.

## Snapshots

- No snapshots of whole screens. A small, intentional snapshot (a serialized value, an icon) is fine; review diffs, never
  update them blindly.

## Naming

Pattern: `subject: condition, expected result`

```ts
describe('LoginForm', () => {
  it('shows an error when the password is empty', ...)
})
```

## What to test

- Business logic (hooks, reducers, formatters) with plain unit tests; screens through their user-visible behaviour.
- Device and E2E tests (Detox, Maestro) only for critical flows (sign-in, purchase, onboarding); they are slow and flaky.
- A change to native code is verified manually on a device or simulator; unit tests do not prove it.
