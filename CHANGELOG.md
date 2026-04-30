# Changelog

All notable changes to this project are documented in this file. The
format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## Provenance and divergence from `tree-sitter-tcl`

`tree-sitter-irules` is a fork of
[`tree-sitter-grammars/tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
by Lewis Russell, redistributed under the MIT license (author copyright
retained alongside a new project copyright; see `LICENSE`). This section
summarises the structural deltas from upstream so contributors and
downstream users can see at a glance what is iRules-specific and what is
inherited unchanged. Per-release detail lives in the version sections
below.

**Grammar (`grammar.js`)** — additive only; no upstream rules removed:

- New rule `when_event` for iRules event handlers
  (`when EVENT_NAME [priority N] [timing on|off] { body }`), with
  `event_name` constrained to a screaming-snake identifier and
  `event_modifier` carrying typed `priority: (number)` /
  `timing: on|off` fields. `when_event` is registered in `_builtin`
  alongside the inherited TCL constructs.
- 7 iRules string operators (`starts_with`, `ends_with`, `contains`,
  `equals`, `matches`, `matches_regex`, `matches_glob`) added to
  `binop_expr` at `PREC.equal_string`.

**Queries (`queries/irules/`)** — significant divergence from upstream:

- `when` is `@keyword`, `event_name` is `@constant`, modifier tokens
  (`priority`, `timing`, `on`, `off`) are `@keyword`.
- 105 iRules namespace prefixes (`HTTP::`, `IP::`, `LB::`, `SSL::`,
  `CLIENTSSL::`, `URI::`, `JSON::`, `X509::`, …) tagged
  `@function.builtin` via a single `(#match? "^...::")` predicate.
  Names are sourced from
  [`clouddocs.f5.com/api/irules/iRulesReference.html`](https://clouddocs.f5.com/api/irules/iRulesReference.html)
  and
  [`Commands.html`](https://clouddocs.f5.com/api/irules/Commands.html).
- 45 iRules global commands (`pool`, `virtual`, `drop`, `persist`,
  `table`, `event`, `call`, `clientside`, `serverside`, `connect`,
  `recv`, `send`, `matchclass`, …) tagged `@function.builtin` via
  `(#any-of?)`.
- iRules expression operators tagged `@operator`.
- `static`, `tmm_id` recognised as `@variable.builtin`. Upstream
  TCL-interpreter introspection variables (`tcl_*`, `argc`, `argv`) are
  pruned because they are not present in the BIG-IP iRules runtime.
- Fixed a latent upstream bug: the TCL builtins block was using a dual
  `@function.builtin @function` capture that caused highlighters to
  silently drop `@function.builtin` for `cd`, `exec`, `puts`, `regsub`,
  etc. The fix is queries-only, no grammar change.
- `regexp` parses as its own grammar rule, so its
  `@function.builtin` capture moved from a dead `(#any-of?)` listing to
  a dedicated literal-token rule.

**File-type registration (`tree-sitter.json`)**:

- File extensions are `["irule", "irules"]`; the upstream `"tcl"` entry
  was dropped to avoid a parser-ownership conflict with
  `tree-sitter-tcl` when both grammars are installed in the same
  editor.
- Highlight test fixtures renamed from `test/highlight/*.tcl` to
  `test/highlight/*.irules` to match.

**Bindings (`bindings/`)**:

- Full rename `tree_sitter_tcl` → `tree_sitter_irules` across C, Go,
  Node, Python, Rust, and Swift bindings, including symbol names,
  module names, package metadata, and build inputs.
- Rust `lib.rs` additionally exposes `HIGHLIGHTS_QUERY` via
  `include_str!("../../queries/irules/highlights.scm")`.

**Tests**:

- iRules-specific corpus tests added under `test/corpus/irules.txt`
  (8 tests) and `test/corpus/irules_events.txt` (26 tests, including
  3 ERROR-pinning regressions for documented gaps). Inherited TCL
  corpus tests are kept verbatim as a regression suite for the TCL
  baseline.
- iRules-specific highlight assertions added in
  `test/highlight/irules.irules`, `irules_namespaces.irules`,
  `irules_globals.irules`, and `tcl_builtins.irules`.

**Project conventions**:

- Conventional Commits 1.0.0, Semantic Versioning 2.0.0, Keep a
  Changelog 1.1.0 formally adopted in `AGENTS.md`.
- AI assets (`AGENTS.md`, `CLAUDE.md`, `.claude/skills/`) added for
  AI-assisted contributions.

**Known divergences in semantics from upstream TCL** are documented in
the README "Known limitations" section (`and`/`or`/`not` word operators,
`set static::foo bar`, plain `matches` operator).

## [Unreleased]

### Added

- Initial fork from
  [`tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
  by Lewis Russell, redistributed under the MIT license. Author copyright
  retained alongside a new project copyright.
- Grammar: `when_event` rule for iRules event handlers
  (`when EVENT_NAME [priority N] [timing on|off] { body }`), with
  `event_name` constrained to a screaming-snake identifier and
  `event_modifier` carrying typed `priority: (number)` / `timing: on|off`
  fields.
- Grammar: iRules expression operators (`starts_with`, `ends_with`,
  `contains`, `equals`, `matches`, `matches_regex`, `matches_glob`)
  added to `binop_expr` at `PREC.equal_string`.
- Queries: `queries/irules/highlights.scm` tags `when` as `@keyword`,
  `event_name` as `@constant`, `priority` / `timing` / `on` / `off` as
  `@keyword`, namespace-qualified built-in commands (HTTP::, IP::, TCP::,
  SSL::, LB::, etc., ~80 namespaces) as `@function.builtin`, and iRules
  expr operators as `@operator`.
- Queries: `static` and `tmm_id` recognised as iRules-runtime
  `@variable.builtin` (TCL-only interpreter introspection variables
  inherited from upstream were pruned).
- Tests: 5 corpus tests under `test/corpus/irules.txt` covering simple /
  modified / multi event handlers, iRules string operators, and `RULE_INIT
  timing on`. 2 negative corpus tests confirming `priority`/`timing` /
  `when` parse as plain commands outside `when_event`.
- Tests: `test/highlight/irules.irules` (22 assertions) covering the
  iRules-specific captures end-to-end.
- Bindings: full rename from `tree_sitter_tcl` → `tree_sitter_irules`
  across C, Go, Node, Python, Rust, Swift bindings, including symbol
  names, module names, package metadata, and build inputs.
- Bindings (Rust): `lib.rs` now exposes `HIGHLIGHTS_QUERY` via
  `include_str!("../../queries/irules/highlights.scm")`.
- AI assets: `AGENTS.md`, `CLAUDE.md`, and six skills under
  `.claude/skills/` (`review`, `audit-tests`, `fix-issue`, `issue-plan`,
  `issue-triage`, `lessons-learned`) adapted from
  [`big-code-analysis`](../big-code-analysis) for the tree-sitter grammar
  context.
- Project conventions: Conventional Commits 1.0.0, Semantic Versioning
  2.0.0, and Keep a Changelog 1.1.0 formally adopted in `AGENTS.md`.
- Queries: namespace highlight regex broadened with names cross-checked
  against F5's `iRulesReference.html` and `Commands.html` —
  `AAA`, `ACCESS`, `ACCESS2`, `ACL`, `ADAPT`, `ANTIFRAUD`, `AUTH`, `AVR`,
  `BOTDEFENSE`, `CATEGORY`, `CLASSIFICATION`, `CLIENTSSL`, `DOSL7`,
  `GTP`, `HSL`, `ILX`, `JSON`, `NAME`, `ONECONNECT`, `QOE`, `RESOLVER`,
  `REST`, `REWRITE`, `SCTP`, `SERVERSSL`, `STATS`, `TAP`, `TDS`, `URI`,
  `VDI`, `WAM`, `WEBSSO`, `WS`, `X509`, `XLAT` are now tagged
  `@function.builtin`.
- Queries: iRules global commands (`pool`, `virtual`, `node`, `drop`,
  `reject`, `discard`, `forward`, `clone`, `listen`, `persist`, `snat`,
  `snatpool`, `event`, `call`, `table`, `session`, `sharedvar`,
  `accumulate`, `connect`, `recv`, `send`, `clientside`, `serverside`,
  `peer`, `matchclass`, `findclass`, `findstr`, `getfield`, `decode_uri`,
  `b64encode`, `b64decode`, `domain`, `substr`, `crc32`, `htonl`, `htons`,
  `ntohl`, `ntohs`, `member`, `members`, `nodes`, `active_members`,
  `active_nodes`, `after`, `release`, `collect`) tagged
  `@function.builtin` so editors can distinguish iRules primitives from
  user procs.
- Tests: 23 corpus tests in `test/corpus/irules_events.txt` covering
  lifecycle / connection events (`RULE_INIT`, `SERVER_CONNECTED`,
  `LB_SELECTED`, `PERSIST_DOWN`, `CLIENT_DATA`), HTTP family
  (`HTTP_REQUEST_DATA`, `HTTP_RESPONSE`, collect/release pattern), TLS
  handshake (`CLIENTSSL_HANDSHAKE`, `CLIENTSSL_CLIENTHELLO`), other
  protocols (`DNS_REQUEST`, `SIP_REQUEST`, `WS_CLIENT_FRAME`), modifier
  ordering (priority-then-timing and timing-then-priority), nested command
  substitution (`[IP::addr [IP::client_addr] equals X]`), `switch -glob` /
  `switch -regexp` / fall-through, `static::` reads, sideband
  `connect`/`send`/`recv`, `table` operations, and a real-world
  rate-limiter pattern.
- Tests: `test/highlight/irules_namespaces.irules` (32 assertions) and
  `test/highlight/irules_globals.irules` (37 assertions) with negative
  cases confirming unknown namespaces / user procs do not pick up the
  `@function.builtin` tag.
- Docs: README sections "Recognised iRules surface", "TCL baseline", and
  "Known limitations" sourced from F5 `clouddocs.f5.com/api/irules/`.
- Tests: `test/highlight/tcl_builtins.irules` (12 assertions) locks in
  that inherited TCL builtins (`cd`, `exec`, `puts`, `regsub`, etc.) tag
  as `@function.builtin` — previously silently broken by a dual-capture.
- Tests: 11 additional iRules-globals assertions (`accumulate`, `after`,
  `collect`, `connect`, `recv`, `release`, `send`, `members`, `nodes`,
  `active_members`, `active_nodes`) bring `irules_globals.irules` to 48
  assertions, matching all 45 names in the highlight rule.
- Tests: 3 ERROR-pinning corpus tests in `test/corpus/irules_events.txt`
  hold the documented grammar gaps in place — `not` / `and` word
  operators and `set static::foo bar` — so any future grammar fix
  forces a docs update.

### Fixed

- Queries: TCL builtins block at lines 65-79 of `highlights.scm` was
  using a dual `@function.builtin @function` capture which silently
  caused tree-sitter highlighters to report `@function` instead of
  `@function.builtin` for `cd`, `exec`, `puts`, `regsub`, etc. Dropped
  the redundant `@function` capture so the more-specific tag wins.
- Queries: `regexp` was a dead listing in the TCL builtins
  `(#any-of?)` predicate because `regexp` parses as its own grammar
  rule (`(regexp ...)`), not a generic `(command ...)`. Replaced with a
  dedicated `"regexp" @function.builtin` literal-token capture.
- Docs: README "TLS" namespace group now lists the `TLS` namespace
  itself (it was named in the regex but missing from the group cell).

### Changed

- File-type registration in `tree-sitter.json` is `["irule", "irules"]`;
  the upstream `"tcl"` entry was dropped to avoid a parser-ownership
  conflict with `tree-sitter-tcl` when both grammars are installed in the
  same editor.
- Highlight test files renamed from `test/highlight/*.tcl` to
  `test/highlight/*.irules` to match the file-type registration.
- Queries: iRules globals highlight rule uses a single
  `@function.builtin` capture (no dual `@function`) so the more-specific
  capture wins precedence over the generic `(command name) @function`
  rule.

[Unreleased]: https://github.com/TODO-OWNER/tree-sitter-irules/compare/HEAD...HEAD
