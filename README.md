# tree-sitter-irules

[![CI](https://github.com/dekobon/tree-sitter-irules/actions/workflows/ci.yml/badge.svg)](https://github.com/dekobon/tree-sitter-irules/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A [tree-sitter](https://tree-sitter.github.io/tree-sitter/) parser for F5
[iRules](https://clouddocs.f5.com/api/irules/) — the TCL-derived scripting
language used to program traffic management on F5 BIG-IP.

Repository: <https://github.com/dekobon/tree-sitter-irules>.

iRules are syntactically a dialect of TCL with three additions:

- **Event handlers**: `when CLIENT_ACCEPTED { ... }`, with optional
  `priority N` and `timing on|off` modifiers.
- **Namespace-qualified built-in commands**: `HTTP::host`, `IP::client_addr`,
  `LB::server`, `SSL::cert`, `TCP::respond`, etc.
- **Extra expression operators** on top of TCL's `eq`/`ne`/`in`/`ni`:
  `starts_with`, `ends_with`, `contains`, `equals`, `matches`,
  `matches_regex`, `matches_glob`.

This grammar is built as an extension of
[`tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
by Lewis Russell, redistributed under the MIT license. See `LICENSE`.

## Recognised iRules surface

Names below come from F5's authoritative sources:
[`Commands.html`](https://clouddocs.f5.com/api/irules/Commands.html),
[`iRulesReference.html`](https://clouddocs.f5.com/api/irules/iRulesReference.html),
[`Operators.html`](https://clouddocs.f5.com/api/irules/Operators.html), and
[`when.html`](https://clouddocs.f5.com/api/irules/when.html). The list
reflects what `queries/irules/highlights.scm` will tag as
`@function.builtin`; commands outside the list still parse, they just fall
through to the generic `@function` capture.

**Namespaced commands** (`<NS>::<command>`):

| Group | Namespaces |
|-------|-----------|
| Transport / IP | `IP`, `TCP`, `UDP`, `SCTP`, `LINK`, `VLAN`, `ROUTE`, `DATAGRAM`, `DHCP`, `FLOW`, `FLOWTABLE`, `IPFIX`, `LSN`, `NSH`, `PCP` |
| TLS | `SSL`, `CLIENTSSL`, `SERVERSSL`, `TLS`, `X509`, `IKE` |
| HTTP | `HTTP`, `HTTP2`, `HTTP3`, `WS`, `WEBSOCKET`, `CACHE`, `COMPRESS`, `REWRITE`, `STREAM`, `URI`, `JSON`, `XML`, `HTML`, `SSE` |
| Other application | `DNS`, `SIP`, `SDP`, `RTSP`, `FTP`, `MQTT`, `FIX`, `DIAMETER`, `RADIUS`, `ICAP`, `GTP`, `TDS`, `NTLM`, `MR`, `GENERICMESSAGE`, `CONNECTOR`, `DNSMSG`, `IMAP`, `POP3`, `SIPALG`, `SMTPS`, `SOCKS` |
| Load balancing / virtual | `LB`, `POOL`, `NODE`, `MEMBER`, `VIRTUAL`, `SNAT`, `SNATPOOL`, `PERSIST`, `PROFILE`, `PROXY`, `ONECONNECT`, `RATELIMIT`, `SCRUBBER`, `GTM`, `TMM`, `TMSH`, `BWC`, `ISESSION`, `IVS`, `L7CHECK` |
| Access / security | `ACL`, `ACCESS`, `ACCESS2`, `AAA`, `AUTH`, `WEBSSO`, `VDI`, `WAM`, `TAP`, `ASM`, `BOTDEFENSE`, `ANTIFRAUD`, `DOSL7`, `CATEGORY`, `CLASSIFICATION`, `CLASSIFY`, `CLASS`, `ADM`, `APM`, `ECA`, `POLICY`, `PSC` |
| Adaptation / data | `ADAPT`, `PEM`, `AVR`, `STATS`, `TABLE`, `SESSION`, `EVENT`, `LOG`, `LOGGING`, `MEMORY`, `RESOLV`, `RESOLVER`, `REST`, `XLAT`, `NAME`, `HSL`, `ILX`, `QOE`, `MATRIX`, `NS`, `ISTATS`, `MESSAGE`, `SIDEBAND` |
| Crypto / encoding | `CRYPTO`, `AES`, `DES`, `RC4`, `HMAC`, `MD5`, `SHA1`, `SHA256`, `SHA384`, `SHA512`, `B64`, `HEX`, `BIGNUM`, `ASN1` |

**Global (non-namespaced) iRules commands** also tagged as
`@function.builtin`: `accumulate`, `active_members`, `active_nodes`,
`after`, `b64decode`, `b64encode`, `call`, `clientside`, `clone`,
`collect`, `connect`, `crc32`, `decode_uri`, `discard`, `domain`, `drop`,
`event`, `findclass`, `findstr`, `forward`, `getfield`, `htonl`, `htons`,
`listen`, `matchclass`, `member`, `members`, `node`, `nodes`, `ntohl`,
`ntohs`, `peer`, `persist`, `pool`, `recv`, `reject`, `release`, `send`,
`serverside`, `session`, `sharedvar`, `snat`, `snatpool`, `substr`,
`table`, `virtual`.

**Event names** are intentionally open: anything matching
`/[A-Z][A-Z0-9_]*/` parses as an `event_name`. F5 documents 200+ events
across protocol families and adds new ones each BIG-IP release; encoding
a closed set in the parser would force a regen on every release. Validate
event spellings in a linter, not the parser.

## TCL baseline

iRules is a TCL 8.4 dialect (per F5
[K6091](https://my.f5.com/manage/s/article/K6091)). TCL 8.5 features
(`dict`, `lassign`, `**` operator, expanded `lsearch` switches) and
TCL 8.6 features (`try`/`on error`/`finally`, `lmap`, `throw`) are
available on BIG-IP 12.x and later when explicitly enabled. The grammar
follows the `tree-sitter-tcl` baseline, so 8.5/8.6 syntax parses
fine — but keep in mind that older BIG-IP runtimes will reject those
constructs.

A subset of TCL commands is **disabled at runtime** in iRules for safety
(`exec`, `file`, `open`, `socket`, and others; see F5's
[`DisabledTclCommands.html`](https://clouddocs.f5.com/api/irules/DisabledTclCommands.html)).
The parser does **not** enforce the disabled list — disabled commands
parse as ordinary TCL commands. Linting/validation is out of scope here.

## Known limitations

- **`set` with namespace-qualified target** (`set static::foo bar`) parses
  with an `(ERROR ...)` around the `::foo` segment because the `set` rule
  binds to a single `id` and the immediate-`::` extension does not fire
  in that position. Workaround: read via `info exists static::foo`, or
  initialise the variable through `namespace eval` for now.
- **`switch` is partially modeled.** Only the braced-arms form is
  supported. TCL's un-braced trailing `pattern body pattern body …`
  syntax is not modeled. TCL 8.5+ `-matchvar varName` and
  `-indexvar varName` options for `switch -regexp` are not recognised
  and produce `(ERROR ...)` nodes.
- **`try` is partially modeled.** The grammar accepts
  `try body ?on error vars handler? ?finally script?` but not the
  full TCL 8.6 surface: `trap pattern vars handler` clauses and
  multiple handler clauses are not supported.
- **Plain `matches` operator** (no `_glob`/`_regex` suffix) is accepted by
  the grammar but is **not** documented on F5's Operators page. It is
  retained for upstream `tree-sitter-tcl` compatibility; prefer
  `matches_glob` or `matches_regex`.
- **Test-runner hang on certain comment-only headers**: if a
  `test/highlight/*.irules` file's leading comment block contains *both*
  a dot-and-slash heavy URL AND a literal quoted regex token (the
  combination that occurs naturally when documenting the namespace match
  predicate), `npx tree-sitter test` hangs on that file. Each pattern in
  isolation is harmless. Workaround: keep header comments to a single
  line in highlight test files.

## Status

Early. The grammar parses iRules as TCL plus iRules-specific event handlers
and tags iRules namespace commands and globals in `queries/irules/highlights.scm`.

## Building

```sh
git clone https://github.com/dekobon/tree-sitter-irules.git
cd tree-sitter-irules
npm install
npx tree-sitter generate
npx tree-sitter test
```

The committed `src/parser.c` is generated by the exact `tree-sitter-cli`
version recorded in `package-lock.json` and CI pins to that same version,
so contributors must regenerate `parser.c` with the locally-installed CLI
(`npx tree-sitter generate`) — never with a globally-installed one — when
bumping `tree-sitter-cli`. See `AGENTS.md` for the full versioning,
commit, and changelog conventions.

## Using it

Pick the binding for your toolchain. All bindings expose
`tree_sitter_irules` (or the language-idiomatic equivalent) and resolve to
the same `src/parser.c` + `src/scanner.c`.

No release has been tagged yet, so all snippets below resolve from the
default branch. Once a release `vX.Y.Z` is cut, swap each snippet to a
pinned form: Cargo `tag = "vX.Y.Z"` (instead of `branch = "main"`), Go
`@vX.Y.Z` (instead of `@latest`), npm `github:dekobon/tree-sitter-irules#vX.Y.Z`,
pip `git+https://github.com/dekobon/tree-sitter-irules@vX.Y.Z`, or the
published package version once available on the relevant registry.

```toml
# Cargo.toml
[dependencies]
tree-sitter-irules = { git = "https://github.com/dekobon/tree-sitter-irules", branch = "main" }
```

```sh
# Go: resolves to a pseudo-version of the latest commit on main.
go get github.com/dekobon/tree-sitter-irules@latest
```

```jsonc
// package.json
"dependencies": { "tree-sitter-irules": "github:dekobon/tree-sitter-irules" }
```

```toml
# pyproject.toml
[project]
dependencies = ["tree-sitter-irules @ git+https://github.com/dekobon/tree-sitter-irules"]
```

Bindings ship the parser only. Editor / runtime integrations also need
to load `queries/irules/highlights.scm` (and optionally `folds.scm` /
`indents.scm`) for highlighting and structural navigation; consult your
editor's tree-sitter integration docs for how to register the queries.
The Rust binding additionally re-exports the highlights query as
`HIGHLIGHTS_QUERY`.

### Filetype detection

The repo ships `ftdetect/irules.lua` and `ftplugin/irules.lua` for
Neovim. The ftdetect file maps `*.irule` and `*.irules` to filetype
`irules` unconditionally; the ftplugin then calls
`vim.treesitter.start()` for that filetype. Highlighting only renders
once the parser binary and `queries/irules/highlights.scm` are
registered with `nvim-treesitter` (or equivalent) — without that, the
`start()` call is a no-op and the buffer falls back to non-treesitter
highlighting.

iRules are also commonly stored with a plain `.tcl` extension — we
deliberately do **not** claim `.tcl` globally, since most `.tcl` files
on disk are ordinary TCL. To opt specific `.tcl` files into the iRules
parser, pick one of:

- **Modeline** at the top of the file:
  `# vim: set filetype=irules :`
- **Per-project autocmd** in `.nvim.lua` (sourced after `:cd` into the
  project via Neovim's `'exrc'`). Note `vim.fn.getcwd()` is evaluated
  when the autocmd is *defined*, so this snippet belongs in a
  per-project config, not a global `init.lua`:

  ```lua
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = vim.fn.getcwd() .. "/irules/*.tcl",
    callback = function() vim.bo.filetype = "irules" end,
  })
  ```

- **Content-based detection** for files that always start with a `when`
  block:

  ```lua
  vim.filetype.add({
    pattern = {
      [".*%.tcl$"] = function(_, bufnr)
        local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
        if first:match("^%s*when%s+[A-Z][A-Z0-9_]*") then return "irules" end
      end,
    },
  })
  ```

Other editors follow the same pattern: keep `.tcl` mapped to TCL by
default and override per-directory or via a header comment.

## Layout

- `grammar.js` — grammar definition (TCL base + iRules `when` event handler).
- `queries/irules/` — highlight, fold, and indent queries with iRules-aware tags.
- `test/corpus/` — corpus tests (TCL tests inherited; iRules-specific tests in
  `test/corpus/irules.txt`).
- `bindings/` — language bindings (C, Go, Node, Python, Rust, Swift).

## Contributing

- Issues and feature requests:
  <https://github.com/dekobon/tree-sitter-irules/issues>
- Pull requests welcome. Read `AGENTS.md` first — it documents the
  Conventional Commits / SemVer / Keep-a-Changelog conventions, the
  validation gates (`npx tree-sitter generate`, `npx tree-sitter test`,
  `npm run lint`), and the rule that committed `src/parser.c` must be
  generated by the `tree-sitter-cli` version recorded in
  `package-lock.json`.

## License

MIT. See [`LICENSE`](LICENSE). This grammar is a fork of
[`tree-sitter-tcl`](https://github.com/tree-sitter-grammars/tree-sitter-tcl)
by Lewis Russell; original copyright is retained alongside the
`tree-sitter-irules` project copyright.
