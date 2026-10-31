# Spring Boot idioms

Framework-level rules that hold for any Spring Boot repo. Project architecture (package layout, persistence choice,
error format) belongs in the project's own rules, not here.

## Wiring

- Constructor injection only; no field `@Autowired`. Dependencies are `private final`.
- Configuration goes in `@ConfigurationProperties` classes (validated with `@Validated`), not scattered `@Value`.
- Behaviour that differs per environment is selected by profiles and properties, never by `if (env == ...)` in code.

## Layers

- Controllers translate HTTP to a service call and back; no business logic, no repositories.
- Never return or accept `@Entity` types at the API edge: use DTOs (records) and map in the service or a mapper.
- `@Transactional` sits on the service method that defines the unit of work, not on controllers. Do not call a
  transactional service in a loop from a caller that expects one transaction, and do not self-invoke (proxy bypass).
- Use `@Transactional(readOnly = true)` for queries.

## Validation and errors

- Validate at the edge with `jakarta.validation` (`@Valid` on `@RequestBody`, constraints on DTO fields).
- Map exceptions to responses in one `@RestControllerAdvice`; services throw domain exceptions, never `ResponseEntity`.
- Return `Optional` from lookups that may be empty; never as a field or parameter, and never call `get()` unchecked.

## Logging

- SLF4J (`private static final Logger` or `@Slf4j`); no `System.out`, no `printStackTrace()`.
- Log with placeholders (`log.info("order {} created", id)`), never string concatenation; never log secrets or PII.
