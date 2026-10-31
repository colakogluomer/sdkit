# Test-first mindset

Not strict TDD, but a test is considered before code, for every task.

1. **Every Definition of Done item names how it is verified**: `unit test`, `integration test`, `manual check`, or `none: <reason>`. An item with no method is not finished being written.
2. **Decide the test before the code.** If the item can be tested now, write the test first and watch it fail for the right reason (not a compile error), then implement. If it cannot, say why (what blocks it) and record the gap in the proposal; do not silently skip it.
3. **Strictness follows risk.** `high`: the regression test is written by a separate role against real infrastructure and frozen. `medium`/`low`: test-first when the code is testable, with the reason recorded when it is not.
4. **Test the behaviour, not the implementation.** One failing reason per test; error paths and validation before the happy path.
5. **A test counts only if it would fail without the change.** The verifier does not accept a passing test that the diff does not influence.
6. **Never weaken a test to make it pass.** A wrong test is reported to its owner with evidence.
7. **Smallest seam.** If testability needs an abstraction, add only what the call site uses, after asking.
