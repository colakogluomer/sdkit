# Java / Kotlin testing

Style rules for JVM tests. Where tests live and which containers exist are project facts; see `project.md`.

## Naming

Pattern: `subject_condition_expectedResult`

```java
void createOrder_duplicateId_throwsConflict()
void findById_unknownId_returnsEmpty()
```

## Scope

- Plain unit tests for logic, collaborators mocked (Mockito / MockK); no framework context unless the test is about wiring.
- Real infrastructure (database, broker) through Testcontainers, not an in-memory substitute with different semantics.
  Integration modules matching `INTEGRATION_MODULE_GLOB` are compiled but not run by verify.

## Assertions and isolation

- AssertJ (`assertThat`) or Kotest matchers; assert the value and the exact exception, not only that something was thrown.
- No shared mutable state between tests (static fields, singletons, ordering); each test sets up its own data.
- No `Thread.sleep`: use Awaitility or a fake clock.
