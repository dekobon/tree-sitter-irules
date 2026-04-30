# tree-sitter-irules

A [tree-sitter](https://tree-sitter.github.io/tree-sitter/) parser for F5
[iRules](https://clouddocs.f5.com/api/irules/) — the TCL-derived scripting
language used to program traffic management on F5 BIG-IP.

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
| Transport / IP | `IP`, `TCP`, `UDP`, `SCTP`, `LINK`, `VLAN`, `ROUTE` |
| TLS | `SSL`, `CLIENTSSL`, `SERVERSSL`, `TLS`, `X509` |
| HTTP | `HTTP`, `HTTP2`, `HTTP3`, `WS`, `WEBSOCKET`, `CACHE`, `COMPRESS`, `REWRITE`, `STREAM`, `URI`, `JSON`, `XML` |
| Other application | `DNS`, `SIP`, `SDP`, `RTSP`, `FTP`, `MQTT`, `FIX`, `DIAMETER`, `RADIUS`, `ICAP`, `GTP`, `TDS`, `NTLM`, `MR`, `GENERICMESSAGE` |
| Load balancing / virtual | `LB`, `POOL`, `NODE`, `MEMBER`, `VIRTUAL`, `SNAT`, `SNATPOOL`, `PERSIST`, `PROFILE`, `PROXY`, `ONECONNECT`, `RATELIMIT`, `SCRUBBER`, `GTM`, `TMM`, `TMSH` |
| Access / security | `ACL`, `ACCESS`, `ACCESS2`, `AAA`, `AUTH`, `WEBSSO`, `VDI`, `WAM`, `TAP`, `ASM`, `BOTDEFENSE`, `ANTIFRAUD`, `DOSL7`, `CATEGORY`, `CLASSIFICATION`, `CLASSIFY`, `CLASS` |
| Adaptation / data | `ADAPT`, `PEM`, `AVR`, `STATS`, `TABLE`, `SESSION`, `EVENT`, `LOG`, `LOGGING`, `MEMORY`, `RESOLV`, `RESOLVER`, `REST`, `XLAT`, `NAME`, `HSL`, `ILX`, `QOE`, `MATRIX`, `NS` |
| Crypto / encoding | `CRYPTO`, `AES`, `DES`, `RC4`, `HMAC`, `MD5`, `SHA1`, `SHA256`, `SHA384`, `SHA512`, `B64`, `HEX`, `BIGNUM` |

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
(`dict`, `lassign`, `try`/`on error`/`finally`, `lmap`, etc.) are
available on BIG-IP 12.x and later when explicitly enabled. The grammar
follows the `tree-sitter-tcl` baseline, so 8.5 syntax parses fine — but
keep in mind that older BIG-IP runtimes will reject those constructs.

A subset of TCL commands is **disabled at runtime** in iRules for safety
(`exec`, `file`, `open`, `socket`, and others; see F5's
[`DisabledTclCommands.html`](https://clouddocs.f5.com/api/irules/DisabledTclCommands.html)).
The parser does **not** enforce the disabled list — disabled commands
parse as ordinary TCL commands. Linting/validation is out of scope here.

## Known limitations

- **Word-form expression operators** (`and`, `or`, `not`) listed on F5's
  [`Operators.html`](https://clouddocs.f5.com/api/irules/Operators.html)
  are not yet recognised inside `expr` contexts. Use the symbolic forms
  `&&`, `||`, `!` until this is fixed. Code that uses the word forms
  parses with `(ERROR ...)` nodes around the affected expression.
- **`set` with namespace-qualified target** (`set static::foo bar`) parses
  with an `(ERROR ...)` around the `::foo` segment because the `set` rule
  binds to a single `id` and the immediate-`::` extension does not fire
  in that position. Workaround: read via `info exists static::foo`, or
  initialise the variable through `namespace eval` for now.
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
npm install
npx tree-sitter generate
npx tree-sitter test
```

## Layout

- `grammar.js` — grammar definition (TCL base + iRules `when` event handler).
- `queries/irules/` — highlight, fold, and indent queries with iRules-aware tags.
- `test/corpus/` — corpus tests (TCL tests inherited; iRules-specific tests in
  `test/corpus/irules.txt`).
- `bindings/` — language bindings (C, Go, Node, Python, Rust, Swift).
