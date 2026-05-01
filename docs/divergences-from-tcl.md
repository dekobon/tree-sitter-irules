# How iRules diverges from TCL

iRules is the F5 BIG-IP scripting language. Syntactically it is a dialect
of TCL with a small set of language-level additions and a (larger) set of
runtime restrictions. This grammar is forked from
[`tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
by Lewis Russell and adds iRules-specific rules on top.

This document is the source of truth for divergences between
**this grammar and upstream `tree-sitter-tcl`**, and between
**iRules and stock TCL**. It exists primarily to support expert review of
the grammar. Every grammar-level claim cites `grammar.js` by line so a
reviewer can jump straight to the rule under discussion.

---

## TCL baseline

iRules is built on **TCL 8.4** (per F5
[K6091](https://my.f5.com/manage/s/article/K6091)). Newer TCL features —
`dict`, `lassign`, the `**` operator, and expanded `lsearch` switches
(all 8.5); `try` / `on error` / `finally`, `lmap`, `throw` (all 8.6) —
are available on BIG-IP **12.x and later** when the rule's TCL-runtime
version is set accordingly. Older BIG-IP runtimes will reject those
constructs even though they parse here.

Authoritative upstream references: the
[Tcl/Tk 8.4 manual](https://www.tcl-lang.org/man/tcl8.4/), the
[Tcl/Tk 8.5 manual](https://www.tcl-lang.org/man/tcl8.5/), and the
[Tcl/Tk 8.6 manual](https://www.tcl-lang.org/man/tcl8.6/) (parts of which
leak in via newer BIG-IP).

This grammar inherits the upstream `tree-sitter-tcl` baseline (TCL
8.6-ish in practice), so it will happily parse syntax newer than what
some BIG-IP runtimes accept. Version-checking belongs in a linter, not
the parser.

---

## Grammar divergences from upstream `tree-sitter-tcl`

This is the section that matters for grammar review. Each entry is
classified by intent:

- **L** = iRules language-level addition (accepts syntax stock TCL does
  not).
- **M** = grammar-modeling divergence (same syntax as stock TCL, but
  modeled with a dedicated rule + named fields for richer AST shape than
  upstream provides).
- **U** = upstream gap — stock TCL syntax that upstream `tree-sitter-tcl`
  does not currently accept; restored here.
- **P** = plumbing.

Every entry below references this project's `grammar.js`.

### G1. Grammar identity (P)

`grammar.js:23` — `name: 'irules'` (upstream is `name: 'tcl'`). This
renames the generated parser symbol to `tree_sitter_irules` and is what
the bindings under `bindings/{c,go,node,python,rust,swift}/` link
against. The hand-written external scanner in `src/scanner.c` exposes
matching `tree_sitter_irules_external_scanner_*` symbols.

### G2. `_builtin` dispatch arms (mixed)

`grammar.js:53-71` — the inlined `_builtin` rule, which `_command`
dispatches into, is extended with six additional alternatives compared
to upstream:

| Rule | Type | Stock TCL? |
|------|------|-----------|
| `for` | M | yes (TCL `for start test next body`) |
| `switch` | M | yes (TCL `switch` braced-arms form) |
| `when_event` | L | **no** — iRules-only |
| `dict_for` | M | yes (TCL 8.5 `dict for`) |
| `dict_update` | M | yes (TCL 8.5 `dict update`) |
| `dict_with` | M | yes (TCL 8.5 `dict with`) |

Each is detailed below.

### G3. `when_event` (L)

`grammar.js:77-91` — the only top-level rule that introduces syntax
stock TCL does not accept.

```
when_event:
  'when'
  event:    event_name
  modifier: event_modifier*
  body:     braced_word
```

- `event_name` (`grammar.js:84`): `/[A-Z][A-Z0-9_]*/`. Intentionally
  open: F5 documents 200+ events across protocol families and adds new
  ones every BIG-IP release. The grammar does **not** validate that an
  event name is one F5 actually defines — that belongs in a linter. See
  the [iRules Reference](https://clouddocs.f5.com/api/irules/iRulesReference.html).
- `event_modifier` (`grammar.js:88-91`): exactly two forms, accepted in
  any order and any count by the grammar:
  - `priority N` — integer; relative ordering of multiple handlers for
    the same event.
  - `timing on|off` — CPU-time profiling toggle.

  Note: F5's
  [`when` documentation](https://clouddocs.f5.com/api/irules/when.html)
  documents each modifier as appearing at most once. The grammar is
  intentionally more permissive (`grammar.js:80` is a plain `repeat`)
  and leaves uniqueness checking to a linter.

The body is a `braced_word`, so the inner script parses as a normal TCL
script (not as a list of `_word_simple` items).

### G4. iRules-specific `expr` operators (L)

`grammar.js:360-365` — at the `equal_string` precedence
(`PREC.equal_string = 80`, the same level as `eq` / `ne`), this grammar
adds seven operators on top of upstream's `eq` / `ne`:

| Operator | Notes |
|----------|-------|
| `starts_with` | iRules-only |
| `ends_with` | iRules-only |
| `contains` | iRules-only |
| `equals` | iRules-only; functionally an `eq` synonym |
| `matches_glob` | iRules-only |
| `matches_regex` | iRules-only |
| `matches` | accepted by this grammar but **not** documented on F5's [Operators page](https://clouddocs.f5.com/api/irules/Operators.html). Retained defensively; prefer `matches_glob` / `matches_regex` |

These bind only in `expr` contexts — that is, inside `if` / `while`
conditions, `expr` arguments, and braced expressions. Outside `expr`,
identical identifiers parse as ordinary command names or words.

### G5. Word-form boolean operators `and` / `or` / `not` (U)

These are stock TCL operators (documented in the TCL `expr` man page)
that upstream `tree-sitter-tcl` omits. F5 also documents them on
[Operators](https://clouddocs.f5.com/api/irules/Operators.html). This
grammar accepts them:

- `not`: `grammar.js:351` — added to `unary_expr`'s prefix choice
  alongside `-`, `+`, `~`, `!`.
- `and`: `grammar.js:370` — added to `and_logical` precedence alongside
  `&&`.
- `or`: `grammar.js:371` — added to `or_logical` precedence alongside
  `||`.

The README "Known limitations" section no longer lists these as
unrecognised — the stale claim was removed.

### G6. `for` (M)

`grammar.js:150-156`:

```
for:
  'for'
  init:      _word     // start script
  condition: expr      // test
  step:      _word     // next script
  body:      _word
```

Upstream `tree-sitter-tcl` does not model `for`; it parses as a generic
`command` with a `word_list`. Modeling it structurally gives editors the
field shape needed for indent / fold / navigation queries. Syntax
accepted is identical to stock TCL.

### G7. `switch` and `switch_arm` (M)

`grammar.js:136-148`:

```
switch:
  'switch'
  ('-exact' | '-glob' | '-regexp' | '-nocase' | '--')*
  value: _concat_word
  '{' (switch_arm | comment | ';')* '}'

switch_arm:
  pattern: braced_word_simple | _concat_word
  body:    _word
```

Three intentional design choices:

1. **Only the braced-arms form is modeled.** TCL also permits
   un-braced trailing `pattern body pattern body …` arguments after
   `value`. Un-braced `switch` is rare in iRules practice and not
   present in the corpus; supporting it would require a separate
   alternation. Comment in `grammar.js:128-130` records this.
2. **The option set is incomplete.** Only `-exact`, `-glob`, `-regexp`,
   `-nocase`, and `--` are recognised (`grammar.js:138`). TCL 8.5+ also
   defines `-matchvar varname` and `-indexvar varname` for
   `switch -regexp`; neither is modeled, so code that uses them
   currently parses with `(ERROR …)`. Adding them would require
   consuming a following identifier rather than just extending the
   choice list.
3. **`comment` and `;` are accepted between arms.** Without this, the
   lexer eats `# foo` as `pattern: "#" body: "foo"`, which is a real
   iRules-authored shape. Comment in `grammar.js:131-135` records this.

The `default` arm is recognised by `queries/irules/highlights.scm:62-68`,
not the grammar — `default` is just a pattern at parse time.

### G8. `dict for` / `dict update` / `dict with` (M)

`grammar.js:93-118`. Three TCL 8.5 `dict` subcommands take a trailing
script body, and upstream `tree-sitter-tcl` parses none of them
structurally. This grammar adds dedicated rules:

```
dict_for:
  'dict' 'for'
  variables: arguments        // {keyVar valueVar}
  value:     _concat_word
  body:      braced_word

dict_update:
  'dict' 'update'
  variable:  _concat_word
  _concat_word*
  body:      braced_word

dict_with:
  'dict' 'with'
  variable:  _concat_word
  _concat_word*
  body:      braced_word
```

The grammar accepts an arbitrary count of `_concat_word` items between
`variable` and `body`. TCL's actual semantics for `dict_update` are
*alternating key / varName pairs* (so an even count) and for `dict_with`
are an *optional key path* (any count, including zero). Neither
constraint is enforced — pair-structure validation belongs in a linter.

Other `dict` subcommands (`dict get`, `dict set`, `dict exists`,
`dict keys`, `dict create`, …) parse as ordinary commands.

### G9. `command` rule `dict` alias (M)

`grammar.js:188-195` — the `command` rule's `name` field is:

```js
field('name', choice($._word, alias('dict', $.simple_word)))
```

The literal `dict` is promoted to a keyword by the `dict_for` /
`dict_update` / `dict_with` rules. Without the alias, generic forms like
`dict get $d k` or `dict set d k v` would fail to lex `dict` as a
command name. The aliased token still presents as `simple_word` in the
AST so highlights and downstream tooling are unaffected. Comment in
`grammar.js:189-192` records this.

### G10. Inherited rules with no behavioural change

**Every rule not enumerated in G1-G9 is byte-for-byte identical to
upstream `tree-sitter-tcl`.** Verified by `diff` of the two `grammar.js`
files: outside G1-G9 there are zero hunks.

Concretely, the following are unchanged: the precedence table
(`grammar.js:1-18`); `externals`, `inline`, `extras`; `source_file`,
`_terminator`, `comment`, `_command`; `regexp`, `while`, `expr_cmd`,
`foreach`, `global`, `namespace`, `try`, `finally`; `command` (apart
from the G9 `dict` alias); `word_list`, `unpack`, `_word`,
`_word_simple`, `_concat_word`; the `id` / `_id_immediate` / `_ident`
family; `array_index`, `variable_substitution`, `braced_word`,
`braced_word_simple`, `set`, `procedure`, `_argument_word`, `argument`,
`arguments`; `number`, `_boolean`; `_expr_atom_no_brace`, `_expr`,
`expr`; `binop_expr` (apart from the G4 string operators and the G5
`and` / `or` additions); `ternary_expr`; `unary_expr` (apart from the
G5 `not` addition); `if` / `else` / `elseif`, `_conditional`, `catch`;
`quoted_word`, `escaped_character`, `_quoted_word_content`,
`command_substitution`, `simple_word`.

---

## Known grammar limitations

These are gaps a reviewer should be aware of:

### `set` with namespace-qualified target

```tcl
set static::foo bar
```

…parses with an `(ERROR …)` node around `::foo`. The `set` rule
(`grammar.js:264-271`) binds to a single `id` and the immediate-`::`
extension does not fire in that position. Workarounds: `info exists
static::foo` for reads, or initialise via `namespace eval`. Tracked in
`README.md` "Known limitations".

### Un-braced `switch`

See G7 above. Stock TCL accepts both forms; this grammar models only
the braced-arms form.

### `switch -matchvar` / `switch -indexvar`

See G7 above. Both options exist in TCL 8.5+ but are not modeled, so
`switch -regexp -matchvar v …` and `switch -regexp -indexvar v …`
currently parse with `(ERROR …)`.

---

## Out-of-scope (not grammar divergences)

The following are part of the iRules surface but **do not affect the
parse tree** — they only affect highlighting, runtime behaviour, or
documentation. A grammar reviewer can skip these for parser correctness;
they are listed here for completeness.

### Namespace-qualified built-in commands (highlight-only)

TCL allows `::`-qualified command names for user code already; the
grammar (`id` rule, `grammar.js:242-245`, and the immediate-`::` token)
parses arbitrary `FOO::bar` without iRules awareness. The list of F5
namespaces tagged as `@function.builtin` lives in the regex at
`queries/irules/highlights.scm:24` and is reproduced in `README.md`.
Authoritative F5 sources: the
[iRules Reference](https://clouddocs.f5.com/api/irules/iRulesReference.html)
and the
[Master list of iRule Commands](https://clouddocs.f5.com/api/irules/Commands.html).

Examples: `HTTP::host`, `IP::client_addr`, `LB::server`, `SSL::cert`,
`TCP::respond`, `TABLE::set`, `CRYPTO::hash`.

### Global (non-namespaced) iRules commands (highlight-only)

These behave as ordinary TCL commands at parse time. The list lives in
the `(#any-of? @function.builtin …)` predicate at
`queries/irules/highlights.scm:97-143` and is reproduced in `README.md`.
Authoritative: F5's
[Master list of iRule Commands](https://clouddocs.f5.com/api/irules/Commands.html).
`after` is the only entry on the list whose name shadows a stock TCL
command (`after ms ?script?`); the iRules form has different runtime
semantics tied to the BIG-IP scheduler but identical surface syntax.

### iRules-specific built-in variables (highlight-only)

`queries/irules/highlights.scm:50-55` tags two identifiers as
`@variable.builtin`:

- `static::*` — persists across rule invocations within the same TMM
  process; commonly used to cache compiled regexes / lookup tables.
- `tmm_id` — numeric ID of the TMM (Traffic Management Microkernel)
  process executing the current invocation.

### Pruned TCL interpreter variables (highlight-only)

Stock-TCL interpreter variables (any `tcl_*` variable, plus `argc` /
`argv`) are intentionally excluded from the `@variable.builtin` capture
because they are not present in the BIG-IP iRules runtime
(`queries/irules/highlights.scm:50-55` comment). Code that references
them parses cleanly but will fail or return empty at runtime on BIG-IP.

### Disabled TCL commands (runtime-only)

A subset of TCL commands is **disabled at runtime** in iRules for
safety, even though they parse as ordinary TCL commands. The grammar
does **not** enforce this list — linting / validation is out of scope.
F5's
[DisabledTclCommands page](https://clouddocs.f5.com/api/irules/DisabledTclCommands.html)
points at per-version AskF5 K-articles for the actual list. Notably
disabled: `exec`, `file`, `open`, `socket`, plus several others (the F5
list is the source of truth and changes over BIG-IP versions).

---

## What this grammar deliberately does not do

- **Validate event names** (the `event_name` regex is open by design).
- **Validate namespace commands** (arbitrary `FOO::bar` parses; only
  highlighting is gated on the curated namespace list).
- **Enforce the disabled-command list** (those commands parse as
  ordinary commands).
- **Enforce TCL-version-gated syntax** (8.4 vs 8.5 vs 8.6 features all
  parse uniformly under the inherited `tree-sitter-tcl` baseline).
- **Model the un-braced form of `switch`** (see G7).
- **Model all `dict` subcommands** (only the three with script-body
  semantics; see G8).

All of the above belong in a linter that runs against the parsed AST.

---

## References

- [F5 iRules wiki](https://clouddocs.f5.com/api/irules/)
  - [Master list of iRule Commands](https://clouddocs.f5.com/api/irules/Commands.html)
  - [iRules Reference](https://clouddocs.f5.com/api/irules/iRulesReference.html)
    (events + commands index)
  - [Operators](https://clouddocs.f5.com/api/irules/Operators.html)
  - [`when` statement](https://clouddocs.f5.com/api/irules/when.html)
  - [Disabled TCL commands](https://clouddocs.f5.com/api/irules/DisabledTclCommands.html)
    (links to per-version AskF5 K-articles)
- [F5 K6091 — TCL version on BIG-IP](https://my.f5.com/manage/s/article/K6091)
- [Tcl/Tk 8.4 manual](https://www.tcl-lang.org/man/tcl8.4/)
- [Tcl/Tk 8.5 manual](https://www.tcl-lang.org/man/tcl8.5/)
- [Tcl/Tk 8.6 manual](https://www.tcl-lang.org/man/tcl8.6/)
- [Upstream `tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
