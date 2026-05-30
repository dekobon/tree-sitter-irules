(comment) @spell @comment

(command name: (simple_word) @function)

; iRules event handlers: `when CLIENT_ACCEPTED { ... }`
"when" @keyword
(when_event
  event: (event_name) @constant)
(event_modifier
  ["priority" "timing" "on" "off"] @keyword)

; dict script-body subcommands: dict for, dict update, dict with
"dict" @keyword
(dict_for "for" @repeat @keyword)
(dict_update "update" @keyword)
(dict_with "with" @keyword)

; Highlight iRules namespace-qualified commands such as
; HTTP::host, IP::client_addr, LB::server. Names are sourced from
; clouddocs.f5.com/api/irules/iRulesReference.html and Commands.html;
; do not add bare-TCL-shaped namespaces here.
(command
  name: (simple_word) @function.builtin
  (#match? @function.builtin "^(AAA|ACCESS|ACCESS2|ACL|ADAPT|ADM|AES|ANTIFRAUD|APM|ASM|ASN1|AUTH|AVR|B64|BIGNUM|BOTDEFENSE|BWC|CACHE|CATEGORY|CLASS|CLASSIFICATION|CLASSIFY|CLIENTSSL|COMPRESS|CONNECTOR|CRYPTO|DATAGRAM|DES|DHCP|DIAMETER|DNS|DNSMSG|DOSL7|ECA|EVENT|FIX|FLOW|FLOWTABLE|FTP|GENERICMESSAGE|GTM|GTP|HEX|HMAC|HSL|HTML|HTTP|HTTP2|HTTP3|ICAP|IKE|ILX|IMAP|IP|IPFIX|ISESSION|ISTATS|IVS|JSON|L7CHECK|LB|LINK|LOG|LOGGING|LSN|MATRIX|MD5|MEMBER|MEMORY|MESSAGE|MQTT|MR|NAME|NODE|NS|NSH|NTLM|ONECONNECT|PCP|PEM|PERSIST|POLICY|POOL|POP3|PROFILE|PROXY|PSC|QOE|RADIUS|RATELIMIT|RC4|RESOLV|RESOLVER|REST|REWRITE|ROUTE|RTSP|SCRUBBER|SCTP|SDP|SERVERSSL|SESSION|SHA1|SHA256|SHA384|SHA512|SIDEBAND|SIP|SIPALG|SMTPS|SNAT|SNATPOOL|SOCKS|SSE|SSL|STATS|STREAM|TABLE|TAP|TCP|TDS|TLS|TMM|TMSH|UDP|URI|VDI|VIRTUAL|VLAN|WAM|WEBSOCKET|WEBSSO|WS|X509|XLAT|XML)::"))

; iRules-specific expression operators on top of TCL's eq/ne/in/ni.
[
  "starts_with"
  "ends_with"
  "contains"
  "equals"
  "matches"
  "matches_regex"
  "matches_glob"
] @operator

"proc" @keyword.function @keyword

(procedure
  name: (_) @variable
)

; iRules-exposed built-in scalars and namespaces. The `tcl_*` and
; `argc`/`argv` interpreter variables from upstream TCL are not present in
; the BIG-IP iRules runtime and have been pruned.
;
; $tmm_id — the built-in TMM identifier variable
(variable_substitution
  (id) @variable.builtin
  (#eq? @variable.builtin "tmm_id"))

; Generic set target. The static:: capture below claims those targets
; via #not-match? so the two patterns are non-overlapping — relying on
; editor pattern-priority order would be fragile.
(set (id) @variable
     (#not-match? @variable "^static::"))

; static:: namespace — variables that persist across event invocations
(variable_substitution
  (id) @variable.builtin
  (#match? @variable.builtin "^static::"))

(set
  (id) @variable.builtin
  (#match? @variable.builtin "^static::"))


(argument
  name: (_) @variable.parameter @variable
)

; Bare-word fallback for rare contexts where static or tmm_id appear as a
; simple_word outside variable_substitution or set.
((simple_word) @variable.builtin @variable
               (#any-of? @variable.builtin
                "static"
                "tmm_id"))


"expr" @function.builtin

; switch keyword and default arm pattern (bare or {braced})
"switch" @keyword
(switch_arm
  pattern: (simple_word) @keyword
  (#eq? @keyword "default"))
(switch_arm
  pattern: (braced_word_simple
    (simple_word) @keyword)
  (#eq? @keyword "default"))

; `regexp` parses as its own grammar rule (see grammar.js), so it is
; captured by literal token below rather than via the generic command
; (#any-of?) predicate.
"regexp" @function.builtin

(command
  name: (simple_word) @function.builtin
  (#any-of? @function.builtin
   "cd"
   "exec"
   "exit"
   "incr"
   "info"
   "join"
   "puts"
   "regsub"
   "split"
   "subst"
   "trace"
   "source"))

; iRules-specific global (non-namespaced) commands sourced from
; clouddocs.f5.com/api/irules/Commands.html. Distinct from TCL builtins;
; tagging as @function.builtin lets editors visually separate iRules
; primitives from user procs.
(command
  name: (simple_word) @function.builtin
  (#any-of? @function.builtin
   "accumulate"
   "active_members"
   "active_nodes"
   "after"
   "b64decode"
   "b64encode"
   "call"
   "clientside"
   "clone"
   "collect"
   "connect"
   "crc32"
   "decode_uri"
   "discard"
   "domain"
   "drop"
   "event"
   "findclass"
   "findstr"
   "forward"
   "getfield"
   "htonl"
   "htons"
   "listen"
   "matchclass"
   "member"
   "members"
   "node"
   "nodes"
   "ntohl"
   "ntohs"
   "peer"
   "persist"
   "pool"
   "recv"
   "reject"
   "release"
   "send"
   "serverside"
   "session"
   "sharedvar"
   "snat"
   "snatpool"
   "substr"
   "table"
   "virtual"))

; Highlight unset and variable arguments as variables
(command
    name: (simple_word) @keyword
    arguments: (word_list) @variable
    (#any-of? @keyword
        "unset"
        "variable"))

(command name: (simple_word) @keyword
         (#any-of? @keyword
          "append"
          "break"
          "catch"
          "continue"
          "default"
          "dict"
          "error"
          "eval"
          "global"
          "lappend"
          "lassign"
          "lindex"
          "linsert"
          "list"
          "llength"
          "lmap"
          "lrange"
          "lrepeat"
          "lreplace"
          "lreverse"
          "lsearch"
          "lset"
          "lsort"
          "package"
          "return"
          "throw"))

[
 "catch"
 "global"
 "namespace"
 "on"
 "set"
 "trap"
 "try"
 "finally"
 ] @keyword

; The result code in `try { ... } on <code> {vars} {body}` parses as the
; first simple_word child of on_handler. Highlight the literal codes as
; keywords so `on error`, `on ok`, etc. read like keywords; integer
; codes and $var substitutions intentionally fall through.
;
; The leading `.` is a tree-sitter query anchor meaning "first named
; child" — without it, the pattern would also match a simple_word
; appearing later in the on_handler subtree (e.g. inside arguments).
(on_handler
  . (simple_word) @keyword
  (#any-of? @keyword "ok" "error" "return" "break" "continue"))

(unpack) @operator

[
 "while"
 "foreach"
 "for"
 ] @repeat @keyword

[
 "if"
 "else"
 "elseif"
 ] @conditional @keyword

[
 "**"
 "/" "*" "%" "+" "-"
 "<<" ">>"
 ">" "<" ">=" "<="
 "==" "!="
 "eq" "ne"
 "in" "ni"
 "&"
 "^"
 "|"
 "&&"
 "||"
 "and"
 "or"
 "not"
 ] @operator

(variable_substitution) @variable
(quoted_word) @string
(escaped_character) @string.escape

[
 "{" "}"
 "[" "]"
 ";"
 ] @punctuation.bracket @punctuation.delimiter

(number) @number

((simple_word) @number
               (#match? @number
                   "^[+-]?[0-9]+$"))


((simple_word) @boolean
               (#any-of? @boolean "true" "false"))

; after apply array auto_execok auto_import auto_load auto_mkindex auto_qualify
; auto_reset bgerror binary chan clock close coroutine dde encoding eof fblocked
; fconfigure fcopy file fileevent filename flush format gets glob history http
; interp load mathfunc mathop memory msgcat my next nextto open parray pid
; pkg::create pkg_mkIndex platform platform::shell pwd re_syntax read refchan
; registry rename safe scan seek self socket source string tailcall tcl::prefix
; tcl_endOfWord tcl_findLibrary tcl_startOfNextWord tcl_startOfPreviousWord
; tcl_wordBreakAfter tcl_wordBreakBefore tcltest tell time timerate tm
; transchan unknown unload update uplevel upvar vwait yield yieldto zlib
