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

Initial fork of
[`tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
by Lewis Russell, redistributed under the MIT license. Author copyright
is retained alongside a new project copyright.

### Added

- **Grammar.** `and`, `or`, and `not` keyword operators added to
  `binop_expr` / `unop_expr`, matching iRules' word-form Boolean operator
  surface alongside the existing `&&` / `||` / `!` symbol operators
  (#5).
- **Tests.** Corpus coverage for the seven iRules-specific expression
  operators (`starts_with`, `ends_with`, `contains`, `equals`, `matches`,
  `matches_regex`, `matches_glob`) and their interaction with the
  word-form Boolean operators (#10).
- **Grammar.** Dedicated `for` rule with `init`, `condition`, `increment`,
  and `body` fields, replacing what previously parsed as a generic
  command (#6).
- **Grammar.** Dedicated `switch` rule with `switch_arm` children,
  exposing pattern/body structure for folds, indents, and highlight
  tooling. Supports `-exact` / `-glob` / `-regexp` / `-nocase` / `--`
  switches, the dash-body fall-through form, bracketed values, and
  `#`-comments / `;` separators between arms (#7).
- **Grammar.** Dedicated `dict_for`, `dict_update`, and `dict_with` rules
  for the three `dict` script-body subcommands, each carrying a `body`
  field. Value-returning forms (`dict get`, `dict set`, `dict create`,
  `dict exists`, `dict keys`, `dict values`, `dict merge`, `dict size`,
  `dict unset`, `dict incr`, `dict append`) continue to parse as generic
  commands (#8).
- **Grammar.** `when_event` rule for iRules event handlers
  (`when EVENT_NAME [priority N] [timing on|off] { body }`), with
  `event_name` constrained to a screaming-snake identifier and
  `event_modifier` carrying typed `priority: (number)` / `timing: on|off`
  fields. Seven iRules expression operators (`starts_with`, `ends_with`,
  `contains`, `equals`, `matches`, `matches_regex`, `matches_glob`)
  added to `binop_expr` at `PREC.equal_string`.
- **Queries.** `queries/irules/highlights.scm` tags `when` as
  `@keyword`, `event_name` as `@constant`, modifier tokens
  (`priority`/`timing`/`on`/`off`) as `@keyword`, ~105 iRules namespace
  prefixes (`HTTP::`, `IP::`, `LB::`, `SSL::`, …) as `@function.builtin`
  via a single `(#match? "^…::")` predicate, 45 iRules global commands
  (`pool`, `virtual`, `drop`, `persist`, `table`, `event`, `call`,
  `clientside`, `serverside`, `connect`, `recv`, `send`, `matchclass`,
  …) as `@function.builtin`, iRules expression operators as `@operator`,
  and `static` / `tmm_id` as `@variable.builtin`. Names sourced from
  F5's `iRulesReference.html`, `Commands.html`, and `Operators.html`.
- **Tests.** Corpus tests under `test/corpus/irules.txt` (8 tests) and
  `test/corpus/irules_events.txt` (26 tests, including 3 ERROR-pinning
  regressions for documented gaps — `and`/`or`/`not` word operators and
  `set static::foo bar`) covering event handler shapes, iRules string
  operators, modifier ordering, nested command substitution, switch
  forms, sideband I/O, and a rate-limiter pattern. Highlight assertions
  in `test/highlight/irules.irules` (22), `irules_namespaces.irules`
  (32), `irules_globals.irules` (48), and `tcl_builtins.irules` (12),
  with negative cases confirming unknown namespaces / user procs don't
  pick up the `@function.builtin` tag. Inherited TCL corpus tests are
  kept verbatim as a regression suite.
- **Bindings.** Full rename `tree_sitter_tcl` → `tree_sitter_irules`
  across C, Go, Node, Python, Rust, Swift — symbol names, module names,
  package metadata, and build inputs. Rust `lib.rs` additionally
  exposes `HIGHLIGHTS_QUERY` via `include_str!(…)`. Node
  `binding_test.js` skips gracefully when the optional `tree-sitter`
  peer is absent. `Cargo.toml` declares `tree-sitter = "0.25"` as a
  dev-dependency so the in-crate test and the lib-doc doctest compile.
- **CI.** `.github/workflows/ci.yml` runs lint + `tree-sitter generate`
  + `tree-sitter test` + `cargo build` / `cargo test` (via
  `parser-test-action`'s `test-rust: true`, pinned to Rust 1.94) on
  Ubuntu, macOS, and Windows. The `tree-sitter-cli` version is
  resolved from `package-lock.json` (validated against a SemVer regex
  before being written to `$GITHUB_OUTPUT`) and passed to
  `setup-action/cli@v2`, so the CI CLI always matches the version that
  generated the committed `src/parser.c`. The `paths` filter is shared
  between `push` and `pull_request` via a YAML anchor and covers every
  metadata file that affects builds.
- **Docs.** README with canonical repo URL, CI / license
  badges, "Recognised iRules surface", "TCL baseline", "Known
  limitations", per-ecosystem install snippets (with guidance for
  swapping each to a pinned `vX.Y.Z` form once a release is cut), a
  query-loading note for editor integrations, the
  `parser.c`-must-match-locked-`tree-sitter-cli` invariant, and a
  Contributing section. AI assets (`AGENTS.md`, `CLAUDE.md`, six
  skills under `.claude/skills/`) tailored for the tree-sitter grammar
  context. Project conventions formally adopted: Conventional Commits
  1.0.0, Semantic Versioning 2.0.0, Keep a Changelog 1.1.0.

### Changed

- **BREAKING.** Rust binding requires Rust 1.94 or newer (`Cargo.toml`
  `edition = "2024"`, `package.rust-version = "1.94"`). The `extern
  "C"` FFI block in `bindings/rust/lib.rs` uses the edition-2024
  `unsafe extern "C"` form.
- **BREAKING.** Peer / runtime dependencies for downstream consumers
  narrowed: Node peer `tree-sitter` `^0.22.4` → `^0.25.0`; Python
  optional `tree-sitter` extra `~=0.21` → `~=0.25`; Go
  `github.com/tree-sitter/go-tree-sitter` `v0.23` → `v0.24.0`; Cargo
  `tree-sitter-language` floor `0.1.0` → `0.1.7`. Consumers on the
  older ranges must bump.
- `package.json` declares `"engines": { "node": ">=20" }` so older
  Node hits a clear `EBADENGINE` warning instead of opaque build
  failures.
- File-type registration in `tree-sitter.json` is `["irule",
  "irules"]`; the upstream `"tcl"` entry was dropped to avoid a
  parser-ownership conflict with `tree-sitter-tcl` when both grammars
  are installed in the same editor. Highlight test files renamed
  from `test/highlight/*.tcl` to `test/highlight/*.irules` to match.
- Build / dev dependencies bumped (no consumer-visible effect):
  `node-addon-api` `^8.2.1` → `^8.7.0`, `node-gyp-build` `^4.8.2` →
  `^4.8.4`, `eslint` `^9.24.0` → `^9.39.4`, `tree-sitter-cli`
  `^0.25.3` → `^0.25.10`, Cargo `cc` `1.0` → `1.2`. Generated
  parser ABI is unchanged at 15.

### Removed

- `eslint-config-google` (unused — `eslint.config.mjs` only loads
  `eslint-config-treesitter` — and unmaintained since 2022).

### Fixed

- Queries: TCL builtins block in `highlights.scm` was using a dual
  `@function.builtin @function` capture which silently caused
  tree-sitter highlighters to report `@function` instead of
  `@function.builtin` for `cd`, `exec`, `puts`, `regsub`, etc.
  Dropped the redundant `@function` capture so the more-specific tag
  wins. Same fix applied to the iRules globals rule.
- Queries: `regexp` was a dead listing in the TCL builtins
  `(#any-of?)` predicate because `regexp` parses as its own grammar
  rule, not a generic `(command …)`. Replaced with a dedicated
  `"regexp" @function.builtin` literal-token capture.
- Docs: README "TLS" namespace group now lists the `TLS` namespace
  itself (named in the regex but missing from the group cell).

[Unreleased]: https://github.com/dekobon/tree-sitter-irules/compare/HEAD...HEAD
