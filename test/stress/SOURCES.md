# Stress-corpus sources

Each file in this directory is a synthetic iRules snippet authored
for this project (MIT-licensed, same as the parent grammar). The
stress test (`bindings/rust/tests/parse_stress.rs`) walks this
directory and asserts the parser produces zero `ERROR` and zero
`MISSING` nodes for every file.

| File | Coverage focus |
|------|---------------|
| `irules_events.irules` | `when` event handlers with `priority` and `timing` modifiers |
| `namespaced_commands.irules` | namespace-qualified built-in commands (`HTTP::`, `IP::`, `TCP::`, `SSL::`, `LB::`) in command and bracketed-substitution positions |
| `control_flow.irules` | if / elseif / else, braced `switch`, `foreach`, `for`, `while`, word-form Boolean operators |
| `expr_operators.irules` | iRules expression operators (`starts_with`, `ends_with`, `contains`, `equals`, `matches_glob`, `matches_regex`) and `not` / `or` |
| `procedures_and_data.irules` | `proc` definitions, `array set`, `dict create` / `dict set`, `string`, `regsub`, `regexp` |
| `try_handlers.irules` | `try` with `finally`, `on error` / `on ok`, and `trap` exception handlers |
| `namespace_and_arrays.irules` | `namespace eval`, `array set` / array indexing, namespace-qualified (`::`) variable substitution |
| `switch_and_dict.irules` | `switch -glob` arms, `dict create` / `dict for`, escaped-character strings |

Adding new stress files is encouraged — keep them syntactically
valid iRules (a strict superset of TCL). Each new file must keep
the integration test green (zero ERROR / zero MISSING).
