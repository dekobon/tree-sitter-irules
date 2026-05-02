# Lessons Learned

Hard-won lessons from developing `tree-sitter-irules`. Each entry
documents a mistake or subtle behavior that cost real debugging time and
is likely to recur.

---

## 1. The Longest-Match Lexer Beats Structured Multi-Token Rules

When a structured rule (e.g., `$.id` defined as `seq(_ident, token.immediate('::'), _ident_imm)`) competes at the same position as a greedy single-token terminal like `simple_word`, the tree-sitter longest-match lexer will prefer whichever token consumes more characters. If `simple_word` can match `static::config_table` in one shot (14 chars) while `_ident` only matches `static` (6 chars), the lexer picks `simple_word` — and the structured rule silently fails, producing an ERROR node around the unconsumed tail.

**`set` with namespace-qualified targets** (#17, `c1864b2`). The `set` rule used `$.id` for the variable target, but `optional($._word_simple)` later in the sequence made `simple_word` a valid lookahead. The lexer consumed the entire `static::config_table` as `simple_word`, leaving `$.id` holding only `static` and emitting `(ERROR (simple_word "::config_table"))`. The fix replaced `$.id` with `alias($.simple_word, $.id)` so the full lexeme is consumed as a single token at the target slot, preserving the `id` node type for downstream queries.

**Lesson:** Before placing a multi-token rule at a position where `simple_word` or `_concat_word` is also valid (directly or via optionals), test-parse a representative input with `tree-sitter parse`. If the structured rule's first token is shorter than what `simple_word` would match, the lexer will prefer `simple_word`. Use `alias($.simple_word, $.node_type)` to get both the greedy match and the desired AST node type.

---

## 2. Dual Captures Silently Downgrade Highlights

A query pattern like `"expr" @function.builtin @function` assigns two capture names to the same node. Tree-sitter's highlighting engine must choose one, and the result depends on the editor's priority rules — many pick the less-specific tag (`@function`), silently downgrading the highlight. The bug is invisible in `tree-sitter test` (which validates parsing, not capture rendering) and only manifests when an actual editor renders the file.

**TCL builtins dual capture** (initial fork, CHANGELOG). The inherited `tree-sitter-tcl` queries used `@function.builtin @function` on `cd`, `exec`, `puts`, `regsub`, and other builtins. The fix dropped the redundant `@function` tag so `@function.builtin` wins unambiguously.

**`expr` keyword missed in the same sweep** (#14, `cadc54d`). The `expr` literal had the identical dual-capture pattern but was overlooked when the TCL builtins fix was applied. It was only caught later when the highlight queries were audited systematically.

**Lesson:** Never use dual captures for "fallback" purposes — the editor, not the query author, decides which tag wins. When fixing a capture pattern, grep the entire highlights file for the same anti-pattern (`@<specific> @<generic>`) rather than fixing only the instance reported in the issue.

---

## 3. Query Captures Must Target the Actual AST Node Type, Not the Imagined One

Writing a query capture based on the *textual form* of the input (e.g., `tmm_id` is a word, so match `(simple_word)`) rather than the *AST node type* the parser actually produces (e.g., `$tmm_id` parses as `(variable_substitution (id))`) results in a capture that never fires in real code. The mismatch is silent — no error, no warning, the highlight test suite stays green because no test exercises the real usage form.

**`@variable.builtin` for `$tmm_id` and `static::`** (#13, `2969c15`). The capture `((simple_word) @variable.builtin (#any-of? @variable.builtin "static" "tmm_id"))` matched the bare words `static` and `tmm_id`, but real iRules code uses `$tmm_id` (node type `variable_substitution`) and `static::foo` (which after the #17 fix parses as `(id)` inside `set`). The bare `simple_word` form almost never appears. The fix added captures targeting `(variable_substitution (id) ...)` and `(set (id) ...)` with `#eq?` / `#match?` predicates.

**Lesson:** Before writing or reviewing a query capture, always run `echo '<representative input>' | tree-sitter parse --stdin` to see the actual node types. Match what the parser produces, not what the source text looks like. Add a highlight test that exercises the dominant real-world usage form, not just the theoretical bare-word case.

---
