---
name: review
description: Audit grammar / query / binding changes for correctness, performance, and quality. Use when asked to review changes, diffs, or pull requests.
---

# Review Changes

Audit the current change set for correctness, performance, security, and
quality problems. Produce concrete, actionable findings.

## Scope

Determine what to review based on `$ARGUMENTS`:

| Argument | Scope |
|----------|-------|
| *(empty)* | Unstaged + staged changes (`git diff HEAD`) |
| `staged` | Staged changes only (`git diff --cached`) |
| `branch` | All commits on current branch vs `main` (`git diff main...HEAD`) |
| `pr <N>` | Pull request diff (`gh pr diff <N>`) |
| `<commit>` | Single commit (`git show <commit>`) |
| `<commit>..<commit>` | Commit range |
| `<path or glob>` | Full-file review (no diff) |

---

## Step 1: Gather diff and context

1. Obtain the diff for the determined scope.
2. List every file touched. Read **full files** — not just hunks. Findings need
   surrounding context.
3. For grammar changes: regenerate (`npx tree-sitter generate`) before
   reasoning about effects. Stale `src/parser.c` / `src/grammar.json` is a
   source of spurious findings. The hand-written `src/scanner.c` is
   independent of regeneration.
4. If `docs/lessons_learned.md` exists, read it and check whether any lesson
   applies.

---

## Step 2: Audit checklist

Apply every applicable question. Record each finding:

```
FINDING: <short title>
FILE: <path>:<line range>
EVIDENCE: <what is wrong and why>
SEVERITY: bug | performance | security | code-smell | test-gap
EFFORT: trivial | small | medium
```

### Grammar correctness (`grammar.js`)

1. Does the new rule conflict with an existing TCL rule? `tree-sitter generate`
   prints conflicts — verify the diff produces zero conflicts.
2. Are precedences correct for new operators? An iRules operator at the wrong
   `PREC` level (e.g. `starts_with` not at `PREC.equal_string`) silently parses
   but produces a wrong tree.
3. Is `token.immediate` used where the grammar requires no whitespace between
   adjacent tokens (e.g. `::` in namespace ids, `(` in array index)?
4. Does the rule introduce ambiguity? Look for: rules whose alternatives can
   match the same prefix without precedence; uses of `repeat($._word)` that
   could match zero or many tokens.
5. For top-level constructs (e.g. `when_event`): is the rule wired into
   `_builtin` (or another producer of `_command`)? An unwired rule will never
   match.
6. Do field names (`field('event', ...)`) match what queries expect?
7. Does the rule preserve compatibility with stock TCL inputs? iRules is a
   superset; nothing legal in TCL should regress.

### Query correctness (`queries/irules/*.scm`)

8. Do all node types referenced exist in the regenerated `src/node-types.json`?
   `Impossible pattern` at runtime means the query references a non-existent
   node.
9. Are field selectors correct? `command name: (id)` is invalid because
   `command.name` is `_word`, which resolves through `simple_word` /
   `braced_word` / `_concat_word` — match on those concrete types.
10. Are `#match?` regex anchors correct? An unanchored regex over names will
    over-match.
11. Are highlight tags consistent with neovim/helix conventions
    (`@function.builtin`, `@constant`, `@operator`, `@keyword`)?

### Binding correctness (`bindings/`)

12. Does every binding call `tree_sitter_irules()` (not the legacy
    `tree_sitter_tcl()`)?
13. Are scanner symbols in `src/scanner.c` named
    `tree_sitter_irules_external_scanner_*` (matching the grammar's name)?
    The scanner is hand-written and not touched by `tree-sitter generate`,
    so any drift must come from a manual edit.
14. Are external scanner symbols listed in the build inputs of every binding
    (`binding.gyp`, `setup.py`, `Package.swift`, Go `binding.go`,
    `bindings/rust/build.rs`)? Missing scanner.c at link time → undefined
    symbol at load time, which `node-gyp` does NOT catch.
15. Do package metadata files (`package.json`, `Cargo.toml`, `pyproject.toml`,
    `tree-sitter.json`, `go.mod`) all use the same name, version, and license?

### Test coverage

16. Does every new grammar rule have a corpus test under `test/corpus/`?
17. Do the corpus tests pin the exact AST shape — including field names — not
    just rule presence?
18. For new highlight captures: is there an entry under `test/highlight/` that
    asserts the capture by name?
19. Are negative tests present where iRules diverges from TCL? E.g. `when` as
    an event keyword should not be confused with `when` as a generic command
    name.

### Performance

20. Are new regex tokens unbounded? `simple_word: /[^!$\s\\\[\]{}();"]+/` is
    fine; a new rule using `/.+/` is not.
21. Does the grammar still pass `npx tree-sitter test` in well under a second?
    A new rule that explodes parser table size shows up in regeneration time
    and `parser.c` size.

### Security

22. Does any change to bindings expose a path that loads an arbitrary `.so`,
    or trusts user-supplied paths without canonicalization?
23. Do scanner edits introduce unbounded loops or unbounded memory growth on
    pathological input?

### Code quality

24. Stale comments referencing the TCL fork in newly added code?
25. Inconsistent naming (`Tcl` vs `Irules`, `tcl` vs `irules`) introduced by
    the diff?

---

## Step 3: Validate findings

For each finding: re-read the evidence, confirm file and line range, discard
anything speculative. Collapse findings sharing a root cause.

If a finding is pre-existing and the diff does not make it worse, mark
"pre-existing" but still report it.

---

## Step 4: Report

```
## Review: <scope description>

### Bugs / Grammar
| # | Finding | File | Effort | Evidence |

### Test gaps
| # | Finding | File | Effort | Evidence |

### Code quality
| # | Finding | File | Effort | Evidence |

### Summary
- Files reviewed: N
- Findings: N
- Verdict: APPROVE | APPROVE WITH COMMENTS | REQUEST CHANGES
```

If zero findings, say so explicitly and state APPROVE.

---

## Guardrails

- Do NOT implement fixes. Review-only.
- Do NOT report findings without concrete evidence (file + line + reasoning).
- Read full files, not just hunks.
- Verify regeneration was run before assessing grammar changes — stale
  `src/parser.c` will mislead you.
