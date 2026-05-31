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
- 136 iRules namespace prefixes (`HTTP::`, `IP::`, `LB::`, `SSL::`,
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
  an ERROR-pinning regression for a documented gap). Inherited TCL
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
the README "Known limitations" section (`set static::foo bar`, partial
`switch` / `try` modeling, plain `matches` operator).

## [Unreleased]

## [0.1.1] - 2026-05-30

### Fixed

- `regexp` now honors `--` as an end-of-options marker, so a pattern whose
  literal text is a recognized switch token (e.g. `regexp -- -nocase $s`,
  `regexp -all -- -- $s`) parses as the pattern instead of collapsing to an
  `(ERROR)` node (#31).

## [0.1.0] - 2026-05-30

Initial fork of
[`tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
by Lewis Russell, redistributed under the MIT license. Author copyright
is retained alongside a new project copyright.

### Added

- **Grammar.** `regexp` rule now accepts all TCL 8.6 switches
  (`-about`, `-expanded`, `-indices`, `-line`, `-linestop`,
  `-lineanchor`, `-nocase`, `-all`, `-inline`, `-start index`, `--`)
  between the keyword and the pattern argument. Forms like
  `regexp -nocase -all -- {pattern} $string matchVar` now produce a
  structured `(regexp ...)` node instead of falling through to generic
  command parsing (#11).
- **Grammar.** `switch` rule now accepts `-matchvar varName` and
  `-indexvar varName` options (TCL 8.5+), and supports the un-braced
  form where pattern/body pairs appear as flat arguments without
  surrounding braces. GLR conflicts resolve the ambiguity between the
  braced-form delimiter and a braced pattern (#15).
- **Grammar.** `try` rule now models `trap pattern variableList script`
  handlers alongside `on code variableList script`, supports multiple
  chained handlers, and accepts any TCL result code (`ok`, `error`,
  `return`, `break`, `continue`, or integer) — not just `error` (#16).
- **Queries.** Added 31 missing F5-documented iRules namespace prefixes
  (`ADM`, `APM`, `ASN1`, `BWC`, `CONNECTOR`, `DATAGRAM`, `DHCP`,
  `DNSMSG`, `ECA`, `FLOW`, `FLOWTABLE`, `HTML`, `IKE`, `IMAP`, `IPFIX`,
  `ISESSION`, `ISTATS`, `IVS`, `L7CHECK`, `LSN`, `MESSAGE`, `NSH`,
  `PCP`, `POLICY`, `POP3`, `PSC`, `SIDEBAND`, `SIPALG`, `SMTPS`,
  `SOCKS`, `SSE`) to the `@function.builtin` capture regex in
  `highlights.scm` (total: 136 prefixes). Updated the README namespace
  table to match. Added highlight assertions for 10 representative new
  namespaces in `test/highlight/irules_namespaces.irules` (#12).

- **Grammar.** `and`, `or`, and `not` keyword operators added to
  `binop_expr` / `unop_expr`, matching iRules' word-form Boolean operator
  surface alongside the existing `&&` / `||` / `!` symbol operators
  (#5).
- **Tests.** Corpus coverage for the seven iRules-specific expression
  operators (`starts_with`, `ends_with`, `contains`, `equals`, `matches`,
  `matches_regex`, `matches_glob`) and their interaction with the
  word-form Boolean operators (#10).
- **Grammar.** Dedicated `for` rule with `init`, `condition`, `step`,
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
  `test/corpus/irules_events.txt` (26 tests, including an ERROR-pinning
  regression for `set static::foo bar`) covering event handler shapes,
  iRules string
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
- **CI.** `.github/workflows/ci.yml` runs lint, `tree-sitter generate`,
  `tree-sitter test`, and `cargo build` / `cargo test` (via
  `parser-test-action`'s `test-rust: true`, pinned to Rust 1.94) on
  Ubuntu, macOS, and Windows. The `tree-sitter-cli` version is
  resolved from `package-lock.json` (validated against a SemVer regex
  before being written to `$GITHUB_OUTPUT`) and passed to
  `setup-action/cli@v2`, so the CI CLI always matches the version that
  generated the committed `src/parser.c`. The `paths` filter is shared
  between `push` and `pull_request` via a YAML anchor and covers every
  metadata file that affects builds. Additional jobs: clippy
  (`-D warnings`), `cargo deny` (advisories / licenses / bans /
  sources), and repo tooling (`typos`, `taplo format --check`,
  `markdownlint-cli2`). All third-party actions SHA-pinned with a
  `# vN` comment so Dependabot can still bump them. A scanner-diff-
  gated `fuzz` job runs `tree-sitter/fuzz-action` only when
  `src/scanner.c` changed, with a `HEAD^` guard for shallow clones.
- **CI.** `.github/workflows/codeql.yml` runs CodeQL on every push and
  PR (and weekly on a schedule) across `actions`, `c-cpp`,
  `javascript-typescript`, `python`, `go`, and `rust`. Configuration
  in `.github/codeql/codeql-config.yml` excludes generated parser
  outputs so analysis focuses on the hand-written scanner and binding
  code.
- **Release pipeline.** `.github/workflows/release.yml` is triggered by
  pushing a `vX.Y.Z` tag and publishes to all three registries via
  OIDC Trusted Publishing — crates.io
  (`rust-lang/crates-io-auth-action`), npm (`npm publish
  --provenance`, requires npm ≥ 11.5.1), and PyPI
  (`pypa/gh-action-pypi-publish` with `skip-existing: true`). A
  `validate` job cross-checks that the tag matches the version in
  `tree-sitter.json`, `package.json`, `pyproject.toml`, and
  `Cargo.toml`, that the package names on each registry match
  expectations, and that `CHANGELOG.md` has a section for the version.
  `npm-prebuilds` and `pypi-wheels` matrix-build native artifacts for
  Ubuntu / macOS / Windows. After all three publishes succeed a
  `github-release` job extracts the matching CHANGELOG section and
  creates the GitHub Release with `gh release create --verify-tag`.
  Re-runs on the same tag (`workflow_dispatch --ref vX.Y.Z`) are
  idempotent — each publish job short-circuits if the version already
  landed on its registry.
- **Repo policy.** Added `dependabot.yml` covering all six package
  ecosystems (github-actions, npm, cargo, gomod, pip, swift) with
  grouped minor/patch PRs; `eslint` major is held via `ignore` (the
  pinned config supports only eslint 9). A `tree-sitter-cli` bump is
  allowed to land: `regenerate.yml` regenerates `parser.c` on the
  Dependabot PR and the CI "verify generated parser artifacts are up to
  date" step blocks any drift. Added `CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, bug / feature issue templates, a PR template,
  and `docs/cutting-a-release.md` documenting the Trusted-Publishing
  setup and per-release procedure. Repo tooling configs:
  `.taplo.toml`, `.typos.toml`, `deny.toml`,
  `.markdownlint-cli2.jsonc`.
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
- **Editor integration.** `ftdetect/irules.lua` ships with the grammar
  so Neovim auto-detects `*.irule` and `*.irules` as filetype `irules`;
  the existing `ftplugin/irules.lua` then calls
  `vim.treesitter.start()`. README gains a "Filetype detection" section
  covering modeline, per-project autocmd, and content-based opt-in
  patterns for users whose iRules are stored as plain `.tcl`.
- **Node binding.** `bindings/node/index.js` now exposes
  `HIGHLIGHTS_QUERY` as a lazy property that reads
  `queries/irules/highlights.scm` on first access (cached thereafter
  by replacing the getter with the string value, matching the upstream
  `tree-sitter` CLI template). Brings the Node binding to parity with
  the Rust binding, which already re-exports the same query.

### Changed

- **BREAKING.** `ternary_expr` is now right-associative (`prec.right`),
  matching TCL/C: `expr {$a ? $b : $c ? $d : $e}` nests as
  `$a ? $b : ($c ? $d : $e)`, where upstream `tree-sitter-tcl`
  (`prec.left`) produced the left-nested tree. Only the AST shape of
  chained ternaries changes; single ternaries are unaffected. See
  `docs/divergences-from-tcl.md` G12.
- **BREAKING.** Node binding `bindings/node/binding.cc` no longer
  exports the `name` field (`require('tree-sitter-irules').name`
  returns `undefined`). The matching `name: string` declaration is
  removed from `bindings/node/index.d.ts`. Upstream
  `Parser.Language.name` has been deprecated since the NAPI migration
  and no other binding exposes it; consumers needing the package
  identifier should read it from `package.json`. The rest of the
  TypeScript declarations are refreshed to match the current upstream
  `tree-sitter` CLI template: `language` is documented `@private` and
  the optional `HIGHLIGHTS_QUERY?: string` field is declared.

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

- Scanner: array-element **reads** via `$arr(idx)` now parse correctly in
  every read position — value (`set x $arr(i)`), command argument
  (`puts $arr($i)`), namespace-qualified (`$static::cache($key)`), `expr`/`if`
  conditions, `foreach`, and `dict` operands. Previously the external
  `_concat` token fired on the `(` immediately following a variable name,
  winning over `array_index`'s `token.immediate('(')` and wrapping the read
  in an `(ERROR)` node. `(` is now excluded from `_concat` (like its partner
  `)`), so the index attaches to the `variable_substitution`. The same fix
  unblocks bareword `name(idx)` array indices in command arguments
  (`puts a(b)`), which now parse as `(simple_word) (array_index …)` via
  `_concat_word` instead of erroring. The write form (`set arr(i) 5`) was
  already correct. Inherited from upstream `tree-sitter-tcl` (#30).
- Grammar: `dict for`, `dict update`, and `dict with` now accept inline
  brace-quoted dict literals and keys — `dict for {k v} {a 1 b 2} {…}`,
  `dict with d {a} {…}`, `dict update d {my key} v {…}`. The value /
  key-path fields previously used `_concat_word`, which lacks
  `braced_word_simple`, so the braced forms produced `(ERROR …)` /
  `(MISSING …)` nodes and misassigned the body. They now use
  `_word_simple` (matching `foreach`), with a
  `[braced_word, braced_word_simple]` conflict to disambiguate a braced
  key from the trailing braced body. Variable- and command-substitution
  values are unaffected.
- Grammar: the `${name}` braced form now produces an `(id)` child in both
  `set` targets and `variable_substitution`, instead of consuming the
  identifier as anonymous tokens. The two rules now share a single
  `_braced_id` definition, so the braced and bare spellings carry the
  same `(id)` shape. Highlight queries keyed on `(id)` — including the
  `static::` and `tmm_id` built-in splits — now fire on
  `set ${static::foo} 1`, `${static::foo}`, and `${tmm_id}` (#19).
- Grammar: `set` no longer emits an ERROR node for namespace-qualified
  variable targets (`set static::foo bar`, `set ns::var 1`,
  `set ::g::v 1`). The target is now captured as a single `(id)` node
  covering the full qualified name (#17).
- Queries: `@variable.builtin` capture now correctly matches `$tmm_id`
  and `static::` namespace variables inside `variable_substitution` and
  `set` nodes, where the previous bare `simple_word` pattern never
  fired in real iRules code (#13).
- Queries: `expr` keyword had a dual `@function.builtin @function`
  capture that could cause editors to display it as generic `@function`
  instead of `@function.builtin`; removed the redundant capture (#14).
- Docs: aligned `docs/divergences-from-tcl.md`, `CHANGELOG.md`, and
  `README.md` with current implementation — added `try` partial
  modeling to known-limitations, documented `regexp` switch-options
  extension, corrected stale ERROR-pinning count (#18).
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

[Unreleased]: https://github.com/dekobon/tree-sitter-irules/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/dekobon/tree-sitter-irules/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dekobon/tree-sitter-irules/releases/tag/v0.1.0
