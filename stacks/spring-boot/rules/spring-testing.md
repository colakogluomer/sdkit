# Spring Boot testing

Style rules for Spring tests. Where tests live and which containers exist are project facts; see `project.md`.

## Naming

Pattern: `subject_condition_expectedResult`

```java
void createOrder_duplicateId_throwsConflict()
void findById_unknownId_returnsEmpty()
```

## Scope

- Prefer plain unit tests (no Spring context) for logic; mock collaborators with Mockito.
- Slice tests for the layer under test: `@WebMvcTest` (controllers, with `MockMvc` and `@MockitoBean`), `@DataJpaTest`
  (repositories), `@JsonTest`.
- `@SpringBootTest` sparingly, for a few end-to-end paths; every distinct configuration creates another cached context.
- Real infrastructure (database, broker) through Testcontainers, not an in-memory substitute with different semantics.
  Integration modules matching `INTEGRATION_MODULE_GLOB` are compiled but not run by verify.

## Assertions and isolation

- AssertJ (`assertThat`) for assertions; `MockMvc` for HTTP; assert status and body, not only the status.
- No shared mutable state between tests (static fields, singletons, ordering); each test sets up its own data.
- No `Thread.sleep`: use Awaitility or a fake clock.
- `@DirtiesContext` is a last resort; fix the leaking state instead.
