# Java / Kotlin idioms

Style rules for JVM code without a framework assumption. Framework choices and module layout are in `project.md`.

## Structure

- Constructor injection or explicit parameters; no static mutable state and no service locators.
- Immutable by default: `final` fields / records in Java, `val` and data classes in Kotlin.
- Null handling is explicit: `Optional` at API returns (never as a field or parameter) in Java, nullable types in Kotlin; no `!!` without a comment saying why it cannot be null.

## Errors and resources

- Catch specific exceptions; never swallow one silently. Wrap with the cause (`new X(msg, cause)` / `throw X(msg, e)`).
- try-with-resources (`use` in Kotlin) for anything closeable.
- Log through SLF4J (or the project's facade) with parameterized messages; no `System.out`, no `printStackTrace()`, no secrets in logs.
- TODOs carry a reference: `TODO(TASK-123)`.
