# Lessons Learned

Hard-won lessons from developing `tree-sitter-irules`. Each entry
documents a mistake or subtle behavior that cost real debugging time and
is likely to recur.

---

## 1. The Longest-Match Lexer Beats Structured Multi-Token Rules

When a structured rule (e.g., `$.id` defined as `seq(_ident, token.immediate('::'), _ident_imm)`) competes at the same position as a greedy single-token terminal like `simple_word`, the tree-sitter longest-match lexer will prefer whichever token consumes more characters. If `simple_word` can match `static::config_table` in one shot (14 chars) while `_ident` only matches `static` (6 chars), the lexer picks `simple_word` — and the structured rule silently fails, producing an ERROR node around the unconsumed tail.

**`set` with namespace-qualified targets** (#17, `5c06b91`). The `set` rule used `$.id` for the variable target, but `optional($._word_simple)` later in the sequence made `simple_word` a valid lookahead. The lexer consumed the entire `static::config_table` as `simple_word`, leaving `$.id` holding only `static` and emitting `(ERROR (simple_word "::config_table"))`. The fix replaced `$.id` with `alias($.simple_word, $.id)` so the full lexeme is consumed as a single token at the target slot, preserving the `id` node type for downstream queries.

**Lesson:** Before placing a multi-token rule at a position where `simple_word` or `_concat_word` is also valid (directly or via optionals), test-parse a representative input with `tree-sitter parse`. If the structured rule's first token is shorter than what `simple_word` would match, the lexer will prefer `simple_word`. Use `alias($.simple_word, $.node_type)` to get both the greedy match and the desired AST node type.

---

## 2. Dual Captures Silently Downgrade Highlights

A query pattern like `"expr" @function.builtin @function` assigns two capture names to the same node. Tree-sitter's highlighting engine must choose one, and the result depends on the editor's priority rules — many pick the less-specific tag (`@function`), silently downgrading the highlight. The bug is invisible in `tree-sitter test` (which validates parsing, not capture rendering) and only manifests when an actual editor renders the file.

**TCL builtins dual capture** (initial fork, CHANGELOG). The inherited `tree-sitter-tcl` queries used `@function.builtin @function` on `cd`, `exec`, `puts`, `regsub`, and other builtins. The fix dropped the redundant `@function` tag so `@function.builtin` wins unambiguously.

**`expr` keyword missed in the same sweep** (#14, `2c07d48`). The `expr` literal had the identical dual-capture pattern but was overlooked when the TCL builtins fix was applied. It was only caught later when the highlight queries were audited systematically.

**Same pathology, separate patterns** (#18 follow-up review). Two distinct query patterns that target the same node share the dual-capture problem even though neither pattern has two `@captures` on one line. The previous queries had `(set (id) @variable)` and `(set (id) @variable.builtin (#match? "^static::"))` — both fire on `set static::foo …`, leaving the winner up to editor pattern-priority. The fix added a `#not-match?` predicate to the generic pattern so the two are mutually exclusive at the predicate level rather than at the editor level.

**Lesson:** Never use dual captures for "fallback" purposes — the editor, not the query author, decides which tag wins. The same applies when *separate* patterns target the same node: gate them with mutually exclusive predicates (`#match?` / `#not-match?`, `#eq?` / `#not-eq?`) rather than relying on pattern order. When fixing a capture pattern, grep the entire highlights file for the same anti-pattern (`@<specific> @<generic>` on one line, or two patterns on the same node-shape) rather than fixing only the instance reported in the issue.

---

## 3. Query Captures Must Target the Actual AST Node Type, Not the Imagined One

Writing a query capture based on the *textual form* of the input (e.g., `tmm_id` is a word, so match `(simple_word)`) rather than the *AST node type* the parser actually produces (e.g., `$tmm_id` parses as `(variable_substitution (id))`) results in a capture that never fires in real code. The mismatch is silent — no error, no warning, the highlight test suite stays green because no test exercises the real usage form.

**`@variable.builtin` for `$tmm_id` and `static::`** (#13, `998bc3b`). The capture `((simple_word) @variable.builtin (#any-of? @variable.builtin "static" "tmm_id"))` matched the bare words `static` and `tmm_id`, but real iRules code uses `$tmm_id` (node type `variable_substitution`) and `static::foo` (which after the #17 fix parses as `(id)` inside `set`). The bare `simple_word` form almost never appears. The fix added captures targeting `(variable_substitution (id) ...)` and `(set (id) ...)` with `#eq?` / `#match?` predicates.

**Lesson:** Before writing or reviewing a query capture, always run `echo '<representative input>' | tree-sitter parse --stdin` to see the actual node types. Match what the parser produces, not what the source text looks like. Add a highlight test that exercises the dominant real-world usage form, not just the theoretical bare-word case.

---

## 4. `_concat_word` Cannot Match a Brace-Quoted Operand — Use `_word_simple`

The grammar carries several "word" rules with deliberately different alternative sets: `_word_simple` includes `braced_word_simple` (a `{...}` literal / list), but `_concat_word` does not. Placing `_concat_word` at a position that should accept an inline brace-quoted literal silently makes the braced form unparseable — and because the GLR parser then backtracks to find *some* valid interpretation, it mis-binds adjacent fields instead of failing cleanly at the offending token.

**Brace-quoted `dict` operands** (`76b85a8`, code-review pass). `dict_for` used `_concat_word` for its `value` field, and `dict_update` / `dict_with` used `repeat($._concat_word)` for their key paths — yet the analogous inherited rule, `foreach`, had correctly used `_word_simple` for its braced list operand. The result: `dict for {k v} {a 1 b 2} {…}` parsed as a top-level `(ERROR)` with `{k v}` orphaned and `{a 1 b 2}` mis-bound to `variables`; `dict with d {a} {…}` and `dict update d {my key} v {…}` produced `(MISSING "\n")` and reparsed the real body as a separate command. The fix switched those fields to `_word_simple`. A corollary surfaced immediately: putting `braced_word_simple` inside a `repeat()` that precedes a trailing `braced_word` body creates a reduce ambiguity (is this `{...}` another key, or the body?), which required declaring a `[braced_word, braced_word_simple]` conflict so GLR keeps the interpretation where the required body is present.

**Lesson:** When a grammar position should accept a brace-quoted word — a dict value, a key path, a list operand — use `_word_simple` (or otherwise include `braced_word_simple`), never `_concat_word`. Cross-check how the inherited rule for the analogous construct models the same slot. The bug is silent under existing tests because `$var` and `[cmd]` operands still parse, so add a corpus test that exercises the *braced* form specifically. If you add `braced_word_simple` into a `repeat()` ahead of a `braced_word` body, expect to declare a `[braced_word, braced_word_simple]` conflict.

---

## 5. A Fixed Limitation Rots Into False Documentation

"Known limitations" lists are written once and rarely revisited. When a grammar gap is later closed, the corresponding limitation entry usually survives — so the docs accumulate claims that *working* features are broken. Nothing in the test suite fails when a documented limitation becomes false, so the rot is invisible until a user (or a reviewer) trusts the stale claim.

**Four simultaneously-stale claims** (`79bfaee`, code-review pass). `README.md` and `docs/divergences-from-tcl.md` stated that namespace-qualified `set` targets (`set static::foo bar`), the un-braced `switch` form, `switch -matchvar` / `-indexvar`, and `trap` / multiple `try` handlers were unsupported and produced `(ERROR)` nodes. Every one of them parsed cleanly — verified by parsing each form. The stale `set` claim even handed a reviewer in this pass a false premise to reason from before it was checked against the parser.

**A manual "alignment" pass is not enough** (#18). Earlier work explicitly set out to "align `docs/divergences-from-tcl.md`, `CHANGELOG.md`, and `README.md` with current implementation" — and *still* left the four false claims above. A one-time human sweep reliably misses entries.

**Lesson:** Treat every documented limitation as a testable assertion. When you fix a limitation, grep both `README.md` and `docs/divergences-from-tcl.md` for it and delete the entry in the same change. Periodically re-verify each surviving limitation by parsing a representative input — a "limitation" that now parses cleanly is a documentation bug. Where practical, pin the limitation as a corpus test that asserts the `(ERROR)` (as `test/corpus/switch.txt` does for the odd-arm un-braced form), so the doc and the parser cannot silently diverge.

---

## 6. A Rule Reachable Only Through `alias()` Is Not Dead Code

A rule whose own production never appears in any `seq` / `choice` can still be load-bearing if it is the *target* of an `alias(x, $.thatRule)`. Such a rule looks like dead code to a naive grep for `$.thatRule`, but deleting it breaks generation (the alias now references an undefined symbol), and "fixing" that by aliasing to a string literal instead silently demotes the node from named to anonymous — breaking every query that matches it by name.

**The `id` rule** (the `set` alias added in `5c06b91`, the shared braced-id alias in `1d5a9dc`; deletion proposed and rejected during the code-review pass). Every `(id)` node in the grammar is produced through `alias($._id_immediate, $.id)` (in `variable_substitution`), `alias($.simple_word, $.id)` (in `set`), and `alias(/[^}]+/, $.id)` (in `_braced_id`). The `id` rule's own `seq(...)` production is unreachable, so a finder recommended deleting it as dead code. But the rule must exist as a *named* rule for those three aliases to target, and `queries/irules/highlights.scm` matches `(id)` extensively (`@variable`, `@variable.builtin`, the `static::` / `tmm_id` splits). Deleting it would have failed `tree-sitter generate`; aliasing to the string `'id'` instead would have made `(id)` anonymous and silently killed those highlights.

**Lesson:** Before deleting a "dead-looking" rule, grep for `alias(` … `$.<rule>)`, not just direct `$.<rule>` references — a rule used only as an alias target is alive. To keep a node type *named* (so queries can match it), the alias target must remain a defined rule; aliasing to a bare string literal produces an anonymous node instead.

---

## 7. An External-Scanner Token Masks `token.immediate()` at the Same Position

The external scanner (`src/scanner.c`) is consulted *before* the normal lexer at every position where one of its tokens is valid. So when an external token and a `token.immediate(...)` are both valid at the same spot, the external token wins — regardless of match length. This is a different mechanism from longest-match contention among normal tokens (lesson #1): the scanner decides on lookahead *classification*, not on how many characters anything would consume, and a zero-width external token can fire and pre-empt a concrete immediate token entirely. The failure is silent and lives in `scanner.c`, a file most `grammar.js` work never opens — so the symptom (an `(ERROR)` node) looks like a grammar bug while the cause is the scanner's character-acceptance set.

**Array-element reads `$arr(idx)`** (#30, `3b5af6c`). `variable_substitution` is `seq(… , optional($.array_index))` and `array_index` opens with `token.immediate('(')`, so the index was *meant* to attach to the read. But the external `_concat` token (the `interleaved1` glue in `_concat_word` / `_word_simple`) accepted any non-whitespace lookahead except `)`, `:`, `}`, `]` — `(` was not excluded. Right after `$arr`, the scanner returned `_concat`, winning over `token.immediate('(')`; the interleave then expected another word piece beginning with `(` (none exists), so the read collapsed to `(ERROR)` in every read position — value, command argument, namespace-qualified, `expr`/`if`, `foreach`, `dict` operand. The write path (`set arr(i) 5`) was unaffected because `set` attaches `array_index` to its bareword target without ever crossing a `_concat` boundary. The fix added `(` to the scanner's exclusion set (alongside its partner `)`), so `_concat` no longer fires there and the immediate token attaches the index. The safety argument that made the one-line change provably non-regressing: *no alternative in `_concat_word` / `_word_simple` begins with `(`*, so a `_concat` boundary at `(` could only ever have led to an error — excluding it cannot break a previously-valid parse. The same fix also unblocked bareword `name(idx)` indices (`puts a(b)`) through `_concat_word`'s `seq($.simple_word, optional($.array_index))`, which had the identical conflict.

**Lesson:** When a `token.immediate(...)` sits at a position where an external token is also valid (commonly a concat/separator token between adjacent word pieces), assume the external token wins and verify by `tree-sitter parse` — an `(ERROR)` around a structurally-valid suffix is the tell. The lever is the scanner's character-acceptance set, not `grammar.js`. Before excluding a character there, prove the change is safe by confirming no grammar alternative reachable at that position *begins* with that character (so the external token could only ever have produced an error). Exclusions come in partner pairs — if you exclude an opener like `(`, check its closer `)` is handled too. Because `scanner.c` is independent of `grammar.js`, neither `tree-sitter generate` nor a grammar-only review will surface this class of bug; pin it with corpus tests over every position the affected rule appears in.

---
