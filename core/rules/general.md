# General Software Development Rules

## Principles

- **DRY**: Extract repeated logic only when it appears 3+ times and has a stable interface. Premature abstraction is worse than duplication.
- **YAGNI**: Do not add functionality not required by the current task. No "might need later" code.
- **Single Responsibility**: Each function/type does one thing. If you need "and" to describe it, split it.
- **No premature optimization**: Write correct code first. Only optimize when a bottleneck is confirmed.

---

## Naming

| Context         | Rule                                    | Example                         |
|-----------------|-----------------------------------------|---------------------------------|
| Functions       | Verb + noun, clear intent               | `parseTeamID`, `buildPaging`    |
| Booleans        | `is`, `has`, `ok`, `valid` prefix       | `isActive`, `ok`, `valid`       |
| Error variables | `err` or `errX` for shadowed ones       | `err`, `errDB`                  |
| Magic values    | Named constants or inline comment       | `limit = 20 // default page`    |

Rules:
- Avoid abbreviations unless domain-standard (`ID`, `URL`, `HTTP`, `SQS`, `MQ`)
- Do NOT use single-letter names except loop counters (`i`, `j`) and receivers (`h`, `r`, `s`)
- Do NOT use `data`, `info`, `manager`, `helper`, `util` as type or function names

---

## Function Size

- Functions MUST fit on one screen (~40-60 lines max)
- If a function has more than 3 levels of nesting: extract a helper
- Prefer early returns over deep nesting

```go
// GOOD: early return
if err != nil {
    return nil, err
}

// BAD: deep nesting
if err == nil {
    // 30 lines of logic
}
```

---

## Error Handling

- Never swallow errors silently
- Never use `_` to discard errors unless explicitly safe
- Wrap errors with context when crossing layer boundaries: `fmt.Errorf("createTeam: %w", err)`
- Always check errors from deferred `Close()` calls in non-trivial paths

---

## Comments

- Comment **why**, not **what**
- Exported types and functions MUST have godoc comments
- Remove dead/commented-out code — do not leave it "just in case"
- TODO comments MUST include a reference: `// TODO(TASK-123): implement squad logic`

---

## Code Readability

- Group related fields/vars together; separate groups with a blank line
- Struct literal field assignment: always use named fields
- No line longer than ~120 characters
- Delete debug/temporary code before committing
