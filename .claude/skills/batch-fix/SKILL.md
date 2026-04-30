---
name: batch-fix
description: Fix multiple GitHub issues on an integration branch. Issues touching different areas (grammar, scanner, queries, bindings, tests) run in parallel worktrees; issues sharing an area or affecting cross-binding code run sequentially. Each goes through fix, simplify, review, and remediation before merging. Use when asked to fix several issues at once.
---

# Batch Fix GitHub Issues

Fix multiple GitHub issues on a single integration branch. Issues are
classified by affected area(s) and triaged for quick-win priority and
cross-issue dependencies, then scheduled into waves where issues touching
different areas run in parallel. Quick wins are front-loaded for fast
feedback. Issues sharing an area, or any issue that touches `bindings/`
(per-language bindings deliberately mirror each other), are serialized to
avoid merge conflicts. Each issue goes through the full pipeline:
investigate, fix, simplify, review, remediate, validate, commit. Successful
fixes are merged to the integration branch. Failures are logged and skipped.

## Arguments

Parse `$ARGUMENTS` as a space-separated list of issue references and flags:
`#42 #57 #63` or `42 57 63` (with or without `#` prefix).

Optional flags:

- `--sequential`: force single-issue waves (no parallel processing). Use
  when issues have cross-area dependencies that would conflict on merge.

Extract the numeric issue numbers. If no issues are provided, abort with:
"Error: provide at least one issue number. Usage: /batch-fix #42 #57 #63"

---

## Step 0: Validate

### 0a: Validate issues exist

For each issue number, run:

```bash
gh issue view <number> --json number,title,state,labels,body,comments --jq '{number, title, state, labels: [.labels[].name], body, comments}'
```

If any issue does not exist or is already closed, warn the user and remove it
from the list. If no valid open issues remain, abort.

Record each issue's number, title, body, labels, and comments for later steps.
This data is reused in Step 2 (classification) and Step 4 (worktree agent
prompts) -- do not re-fetch.

### 0b: Ensure clean working tree

```bash
git status --porcelain
```

If there are uncommitted changes, abort with:
"Error: working tree is dirty. Please commit or stash your changes before
running /batch-fix."

### 0c: Detect isolation mode

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
if [[ "$PROJECT_ROOT" == *".claude/worktrees/"* ]]; then
  ISOLATION_MODE="worktree"
else
  ISOLATION_MODE="branch"
fi
```

- **Worktree mode**: Agents are launched with `isolation: "worktree"` and run
  in parallel (existing behavior).
- **Branch mode**: Agents are launched WITHOUT `isolation: "worktree"` and run
  sequentially using feature branches. All agents in a wave MUST be processed
  one at a time (they share the working directory).

Record `ISOLATION_MODE` for use in Step 4.

---

## Step 1: Create integration branch

Determine a unique branch name. Try `fix/batch-YYYY-MM-DD` first, then
append a sequence number if it already exists:

```bash
DATE=$(date +%Y-%m-%d)
BRANCH="fix/batch-${DATE}"
SEQ=2
while git rev-parse --verify "$BRANCH" >/dev/null 2>&1; do
  BRANCH="fix/batch-${DATE}-${SEQ}"
  SEQ=$((SEQ + 1))
done
git checkout -b "$BRANCH" main
```

Record the branch name as `INTEGRATION_BRANCH`.

---

## Step 2: Classify and triage issues

For each issue, determine which area(s) it affects and assess complexity.
This lightweight triage improves wave scheduling without adding API calls
(all data was cached in Step 0a).

### 2a: Area classification

The project areas are:

- `grammar` — `grammar.js` (rules, precedence, fields). Generated outputs
  `src/parser.c`, `src/grammar.json`, `src/node-types.json` are touched
  whenever this area changes.
- `scanner` — `src/scanner.c`, the hand-written external scanner for
  `_concat` / `_immediate` tokens.
- `queries` — `queries/irules/*.scm` (highlights, folds, indents).
- `bindings` — per-language wrappers under `bindings/{c,go,node,python,rust,swift}/`.
  **All bindings expose `tree_sitter_irules()` and are siblings — a bug in one
  binding often exists in others.**
- `tests` — `test/corpus/*.txt` and `test/highlight/*.tcl`.
- `ci` — `.github/workflows/**`.
- `docs` — `README.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/`.
- `deps` — `package.json`, `Cargo.toml`, `pyproject.toml`, `tree-sitter.json`,
  `go.mod`, `Package.swift`, `binding.gyp`, `setup.py`, `Makefile`.

Use these signals in priority order:

1. **Labels**: GitHub labels matching area names map directly to areas.
2. **Title/body keywords**: Look for area names, file paths, or distinctive
   terms:
   - "grammar", "rule", "precedence", "ambiguity", "node type", "field",
     "AST", `grammar.js`, "when_event", "event_name", `binop_expr` ->
     `grammar`
   - "scanner", "external scanner", `scanner.c`, "_concat", "_immediate",
     "tokenizer" -> `scanner`
   - "highlight", "capture", "fold", "indent", `.scm`, `#match?`, "injection"
     -> `queries`
   - "binding", "node binding", "rust binding", "python binding",
     "go binding", "swift binding", "c binding", "build.rs", "setup.py",
     "binding.gyp", `tree_sitter_irules()` -> `bindings` with
     `cross_lang: true` (see special case below)
   - "corpus test", "highlight test", `test/corpus/`, `test/highlight/`,
     "regression test" -> `tests`
   - "workflow", "CI", "GitHub Actions", `.github/workflows/` -> `ci`
   - "README", "AGENTS.md", "CLAUDE.md", "CHANGELOG", "doc", "documentation"
     -> `docs`
   - "version bump", "tree-sitter-cli version", "package metadata",
     "Makefile", "package-lock.json", "Cargo.lock" -> `deps`
3. **Ambiguous**: If the area cannot be determined from labels or keywords,
   classify as `unknown`.

**Special case — `bindings/` and cross-binding code**: The per-language
bindings under `bindings/<lang>/` deliberately mirror each other; a build
input or symbol mismatch in one binding often exists in several. Issues that
touch this directory (other than a single, language-specific binding bug
clearly scoped to one wrapper) should be flagged `cross_lang: true`. These
are NOT cross-area, but they require sequential handling because parallel
agents would each touch sibling binding files and conflict on merge. Treat
`cross_lang: true` like `cross_area: true` for scheduling — schedule in its
own wave.

**Special case — `grammar` ripple effects**: Grammar changes regenerate
`src/parser.c`, `src/grammar.json`, and `src/node-types.json`. They commonly
require updates to `queries/irules/*.scm` (capture names track AST node
types) and `test/corpus/*.txt` (expected ASTs change). Flag a grammar issue
`cross_area: true` when the body explicitly mentions renaming a node,
removing a field, or changing AST shape. Pure additive grammar changes (new
rule, new optional field) usually do not need cross_area.

### 2b: Quick-win detection

Flag issues as `quick_win: true` if they match **two or more** positive
indicators AND **zero** disqualifiers.

**Positive indicators** (from title, body, and comments):

- References a single specific file path (e.g., `queries/irules/highlights.scm`
  or `test/corpus/expressions.txt`)
- Contains a clear failing-test name, parser error, or capture-name typo
- Mentions a specific grammar rule, query capture, or scanner branch
- Has a "good first issue" or "bug" label
- Body is short (< 500 characters) with a clear reproduction case (input
  iRules snippet + expected vs actual)
- Fix is described in the issue itself (e.g., "should match `equals` token,
  not `=`")

**Disqualifiers** (any one prevents quick-win):

- Requires AST-shape change (new node type, renamed field, removed child)
  that ripples through queries and corpus tests
- Spans multiple areas explicitly ("change grammar.js and update bindings")
- Needs external input or design decision ("should we...?", "RFC")
- References missing iRules language coverage that requires upstream
  research
- Requires a `tree-sitter-cli` version bump
- Has `cross_area: true` or `cross_lang: true` from Step 2a

### 2c: Cross-issue dependency detection

Scan each issue's title, body, and comments for references to other issues
in the current batch:

- Patterns: `depends on #<N>`, `blocked by #<N>`, `after #<N>`,
  `requires #<N>`
- Bare `#<N>` references do NOT imply dependency -- issues commonly
  cross-reference each other for context without ordering constraints
- Only consider references to issue numbers that are in the current batch

If issue A references issue B, record: `A depends_on B`. This means B must
be scheduled in an earlier wave than A.

**Cycle detection**: If dependencies form a cycle (A->B->C->A), log a
warning and drop all edges in the cycle -- treat those issues as independent.

### 2d: Print classification

For each issue, record:

- `area`: the primary affected area name, or `unknown`
- `cross_area`: `true` if the issue clearly spans multiple areas (e.g., a
  grammar AST-shape change that requires query and corpus-test updates),
  `false` otherwise
- `cross_lang`: `true` if the issue touches `bindings/` in a way that
  requires changes mirrored across language bindings
- `quick_win`: `true` if the issue matches the quick-win criteria above
- `depends_on`: list of issue numbers this issue depends on (empty if none)

Print the classification table:

```
## Issue Classification
| Issue | Title | Area | Cross-area | Cross-lang | Quick-win | Depends on |
|-------|-------|------|------------|------------|-----------|------------|
```

---

## Step 3: Schedule waves

Group issues into processing waves. The goal: maximize parallelism while
respecting area conflicts, dependencies, and quick-win priority.

### Rules

1. Two issues can run in the same wave only if they affect **different
   areas** (neither is `unknown`, neither is `cross_area`, neither is
   `cross_lang`, and their area values differ).
2. `unknown`, `cross_area`, and `cross_lang` issues are placed in their own
   wave (one at a time) after all classified issues.
3. If `--sequential` was specified, every issue gets its own wave.
4. **Dependency ordering**: If issue A `depends_on` issue B, B must appear
   in an earlier wave than A. Dependencies take precedence over quick-win
   priority.
5. **Quick-win priority**: Within each area group, quick-win issues are
   scheduled before non-quick-win issues. This front-loads fast fixes into
   early waves, giving rapid feedback and reducing blast radius.
6. User-specified order is preserved as a tiebreaker within each area group
   (after dependency and quick-win sorting).

### Algorithm

```
classified = issues grouped by area (excluding unknown/cross_area/cross_lang)
unclassified = issues marked unknown, cross_area, or cross_lang
deps = dependency graph from Step 2c

# Sort each area group: quick_wins first, then user order
for area in classified:
    classified[area].sort(key=lambda i: (not i.quick_win, user_order(i)))

# Build waves from classified issues
waves = []
scheduled = set()  # issue numbers already assigned to a wave
remaining = copy of classified (dict of area -> [issue list])
while remaining is not empty:
    wave = []
    areas_in_wave = set()
    for area in list(remaining.keys()) sorted by most issues first:
        if area not in areas_in_wave:
            # Find the first issue whose dependencies are all scheduled
            candidate = None
            for issue in remaining[area]:
                if all(dep in scheduled for dep in issue.depends_on):
                    candidate = issue
                    break
            if candidate is not None:
                remaining[area].remove(candidate)
                wave.append(candidate)
                areas_in_wave.add(area)
    # Clean up empty area groups after the wave is built
    remaining = {a: issues for a, issues in remaining if issues is not empty}
    # Guard against deadlock from unresolvable dependencies
    if wave is empty and remaining is not empty:
        # Force-schedule one issue to break the deadlock
        area = first key of remaining
        issue = remaining[area].pop(0)
        wave = [issue]
        remaining = {a: issues for a, issues in remaining if issues is not empty}
    for issue in wave:
        scheduled.add(issue.number)
    waves.append(wave)

# Append unclassified issues as single-issue waves (respecting dependencies)
pending = list(unclassified)
while pending:
    for issue in pending:
        if all(dep in scheduled for dep in issue.depends_on):
            waves.append([issue])
            scheduled.add(issue.number)
            pending.remove(issue)
            break
    else:
        # Deadlock -- force-schedule the first pending issue
        issue = pending.pop(0)
        waves.append([issue])
        scheduled.add(issue.number)
```

Print the wave plan:

```
## Processing Plan
Isolation: <worktree (parallel) | branch (sequential)>
Wave 1 (parallel): #42 (grammar, quick-win), #57 (queries)
Wave 2 (parallel): #63 (scanner), #71 (tests, quick-win)
Wave 3 (sequential): #80 (cross-lang bindings, depends on #42)
```

In branch mode, also note: "Agents in later waves see changes from earlier
waves (branch mode advantage)."

If all waves are single-issue, note: "All issues serialized (same area,
cross-binding, or unclassified)."

---

## Step 4: Process waves

For each wave, in order:

### 4a: Spawn agents

Use the issue data (title, body, comments) cached from Step 0a to populate
each agent's prompt.

Pass each agent the full agent prompt (see below) with `<ISSUE_NUMBER>`,
`<ISSUE_TITLE>`, and `<ISSUE_BODY>` substituted.

#### Worktree mode (`ISOLATION_MODE=worktree`)

**CRITICAL**: Every agent MUST be launched with `isolation: "worktree"`.
This is a required parameter on the Agent tool call, not optional. Agents
launched without worktree isolation will modify the main project directory,
corrupting the integration branch. Double-check that every Agent tool call
includes `isolation: "worktree"` before sending.

For a **single-issue wave**: launch one Agent with `isolation: "worktree"`
and `model: "opus"`.

For a **multi-issue wave**: launch ALL agents in a single message block
(parallel tool calls). Each agent gets `isolation: "worktree"` and
`model: "opus"`. Do NOT use `run_in_background` -- wait for all agents in
the wave to complete before proceeding.

**Known limitation**: Worktree agents fork from `INTEGRATION_BRANCH` at the
moment they are spawned. Within a single multi-issue wave, agents do not
see each other's in-flight work — they only see the integration-branch tip
that existed when the wave started. The merge in Step 4b reconciles their
results mechanically. For tightly coupled issues that must build on each
other, use `--sequential` or run them as a single `/fix-issue`.

#### Branch mode (`ISOLATION_MODE=branch`)

All agents in a wave MUST be processed **sequentially** (one at a time).
They share the working directory, so parallel execution is FORBIDDEN.

For each issue in the wave, in order:

1. Create a feature branch from the integration branch:

```bash
BRANCH="fix/issue-${ISSUE_NUMBER}"
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git branch -D "$BRANCH"  # stale local branch from prior run
fi
git checkout -b "$BRANCH" "$INTEGRATION_BRANCH"
```

2. Launch ONE Agent with `model: "opus"` (NO `isolation: "worktree"`).

3. On **SUCCESS**:

```bash
git checkout "$INTEGRATION_BRANCH"
git merge "fix/issue-${ISSUE_NUMBER}" --no-edit
git branch -d "fix/issue-${ISSUE_NUMBER}"
```

4. On **FAILED** or **SKIPPED**:

```bash
git checkout -- .
git reset HEAD
git checkout "$INTEGRATION_BRANCH"
git branch -D "fix/issue-${ISSUE_NUMBER}"
```

5. Verify clean state before the next issue. The orchestrator owns
   working-tree cleanup between agents in branch mode (agents are forbidden
   from running `git clean -fd` themselves):

```bash
DIRTY="$(git status --porcelain)"
if [[ -n "$DIRTY" ]]; then
  echo "WARNING: working tree dirty after agent cleanup, cleaning..."
  git checkout -- .
  git clean -fd
fi
```

**Branch mode advantage**: Each feature branch is created from the integration
branch AFTER prior merges, so later agents see earlier fixes. This is an
improvement over worktree mode where agents fork independently from `main`.

### 4b: Process results (after all agents in wave complete)

> **Branch mode**: Skip this step — results are processed inline in Step 4a.

For each agent result in the wave:

The worktree agent returns one of:

- **SUCCESS**: branch name, commit hash, files changed, summary, changelog entry
- **SKIPPED**: reason (issue is invalid, already fixed, or requires no code changes)
- **FAILED**: reason, what was attempted

**On SUCCESS**:

1. Ensure we are on the integration branch:

```bash
git checkout <INTEGRATION_BRANCH>
```

2. Merge the worktree branch:

```bash
git merge <worktree-branch> --no-edit
```

3. If merge conflict occurs, abort and log as FAILED:

```bash
git merge --abort
```

Log: "Issue #N: FAILED -- merge conflict with prior fixes on integration branch"

**On SKIPPED**:

Log the skip reason and continue to the next result. No merge needed.

**On FAILED**:

Log the failure reason and continue to the next result.

### 4c: Wave checkpoint

After merging all successful results from the wave, run a quick build /
parser check on the integration branch:

```bash
git checkout <INTEGRATION_BRANCH>
npx tree-sitter generate
npx tree-sitter test
```

If `tree-sitter generate` or `tree-sitter test` fails after a multi-issue
wave merge, the conflict is between issues in this wave. Identify the
culprit:

1. Record the list of merge commits from this wave (oldest to newest).
2. Reset the integration branch to the state before this wave's merges:

```bash
git reset --hard <pre-wave-commit>
```

3. Re-merge each wave branch one at a time, running `npx tree-sitter generate
   && npx tree-sitter test` after each merge. The first merge that causes
   either step to fail is the culprit.
4. Abort that merge (`git merge --abort`), log the issue as FAILED with
   reason "parse / test conflict with parallel fix in same wave".
5. Continue re-merging the remaining (innocent) branches, skipping only
   the culprit.

Proceed to the next wave.

---

## Step 5: Consolidate CHANGELOG

After all waves are processed, collect CHANGELOG entries from all
successful agents and apply them in a single commit on the integration
branch. This avoids merge conflicts on `CHANGELOG.md`.

### 5a: Update CHANGELOG.md

Collect the `CHANGELOG:` entries from all successful agent results. Add them
to the `[Unreleased]` section of `CHANGELOG.md` under the appropriate
subsection (`### Fixed`, `### Added`, `### Changed`). Each entry should
reference the issue number (e.g., `- Fix incorrect highlight capture for
namespace commands (#42)`).

### 5b: Commit changelog updates

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(changelog): consolidate entries from batch fix

Update CHANGELOG.md with entries from all successfully merged issue fixes
in this batch.
EOF
)"
```

Skip this step if `CHANGELOG.md` did not change.

### 5c: Collect lessons

Gather every non-empty `LESSON:` value from successful agent results and
hold them for Step 7. Do not edit `docs/lessons_learned.md` directly — the
orchestrator only proposes; the user (or `/lessons-learned`) decides which
entries to keep.

---

## Step 6: Final validation

After all waves are processed, if any merges succeeded:

### 6a: Run validation gates on integration branch

```bash
git checkout <INTEGRATION_BRANCH>
npx tree-sitter generate
npx tree-sitter test
npm run lint
```

The committed `src/parser.c` must match what the locally-installed
`tree-sitter-cli` (per `package-lock.json`) produces. Always run
`npx tree-sitter generate` (never a globally-installed CLI) before the final
test pass, and stage `src/parser.c` / `src/grammar.json` / `src/node-types.json`
together with the `grammar.js` change that produced them.

### 6b: Handle validation failure

If only `npm run lint` fails on a fixable issue (e.g., trailing whitespace,
missing semicolon in `grammar.js`), fix it in place rather than bisecting:

```bash
# fix the lint issue manually, then:
git add -u
git commit -m "chore: lint fixes after batch fix"
```

Then re-run all gates from 6a. Only proceed to bisection below if a generate
or test gate fails, or if lint fails in a way that cannot be auto-fixed.

If `tree-sitter test` or any other gate fails, identify and remove the bad
merge:

1. List merge commits on the integration branch since `main`:

```bash
git log main..HEAD --merges --reverse --format="%H %s"
```

2. Test each merge point by checking it out (read-only, no destructive ops):

```bash
# For each merge commit hash, from oldest to newest:
git stash  # save any state
git checkout <merge-commit-hash>
npx tree-sitter generate
npx tree-sitter test
npm run lint
```

3. The first commit where validation fails is the culprit. Return to the
   integration branch and reset to just before it:

```bash
git checkout <INTEGRATION_BRANCH>
git reset --hard <parent-of-bad-merge>
```

4. Re-apply subsequent good merges by cherry-picking or re-merging their
   source branches (skip the bad one).

5. Log the culprit issue as FAILED with reason "validation failure after
   merge with other fixes".

6. Re-run the gates to confirm the branch is clean.

If validation fails on the very first merge (no prior good state), reset to
`main`, log that issue as FAILED, and re-merge the remaining successful
branches.

If validation still fails after removing all suspect merges, something is
fundamentally wrong -- abort and report to the user.

**Recovery from interruption**: If the bisection is interrupted mid-sequence
(timeout, context exhaustion), return to the integration branch and restore
any stashed state:

```bash
git checkout <INTEGRATION_BRANCH>
git stash pop  # if stash was used
```

---

## Step 7: Summary

Print a summary table:

```
## Batch Fix Results
Branch: <INTEGRATION_BRANCH>
Isolation: <worktree | branch>
Mode: <parallel|sequential>

### Processing Plan
<wave plan from Step 3>

### Succeeded
| # | Issue | Title | Area | Quick-win | Wave | Commit | Files Changed |
|---|-------|-------|------|-----------|------|--------|---------------|

### Skipped
| # | Issue | Title | Reason |
|---|-------|-------|--------|

### Failed
| # | Issue | Title | Reason |
|---|-------|-------|--------|

### Statistics
- Issues attempted: N
- Succeeded: N
- Skipped: N
- Failed: N
- Waves executed: N (M parallel, K sequential)
- Total commits on integration branch: N

### Proposed lessons
| # | From issue | Lesson |
|---|------------|--------|
```

Populate **Proposed lessons** with every non-empty `LESSON:` value
collected in Step 5c. Omit the section if no lessons were proposed.

If any lessons were proposed, end with:
"Run `/lessons-learned` to review and add the proposed lessons to
`docs/lessons_learned.md`."

Remind the user: "Integration branch `<INTEGRATION_BRANCH>` is ready for your
review. Merge to main when satisfied, or push to open a PR."

---

## Agent Prompt

**BEGIN AGENT PROMPT**

You are fixing GitHub issue #<ISSUE_NUMBER>: <ISSUE_TITLE>

Issue body:

```
<ISSUE_BODY>
```

You must complete the full fix lifecycle: investigate, implement, simplify,
review, remediate, validate, commit. Do NOT close the GitHub issue -- only
annotate it. The `Fixes #N` commit trailer will close it on merge.

### Setup — Environment Verification (MANDATORY)

Determine your isolation mode:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
if [[ "$PROJECT_ROOT" == *".claude/worktrees/"* ]]; then
  ISOLATION_MODE="worktree"
else
  ISOLATION_MODE="branch"
fi
echo "ISOLATION_MODE=$ISOLATION_MODE PROJECT_ROOT=$PROJECT_ROOT"
```

Verify your branch:

```bash
AGENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "AGENT_BRANCH=$AGENT_BRANCH"
```

**HARD GATE**: If `AGENT_BRANCH` is `main`, `master`, or `HEAD` (detached),
abort immediately — do NOT investigate, do NOT edit any files. Return:

```
STATUS: FAILED
REASON: Agent is on disallowed branch. AGENT_BRANCH=<branch>
ATTEMPTED: Setup verification only — no changes made.
```

Record `AGENT_BRANCH` — you will verify it again before committing.

**BRANCH SAFETY**: Do NOT switch branches. Do NOT run `git checkout`,
`git switch`, or `git checkout -b`. All commits must land on this branch.

In worktree mode: ALL file operations must be within `PROJECT_ROOT`.
**Worktree-safety bans apply**: never delete worktrees, never `cd` to the
main repo, never check out a different branch, never write to files outside
your worktree.

In branch mode: the orchestrator has verified a clean repo before launching you.

### Phase 1: Investigate and Fix

Follow the `/fix-issue` workflow:

1. Re-read project conventions: top-level `CLAUDE.md`, `AGENTS.md`, and any
   rule files under `.claude/rules/` if present.
2. If `docs/lessons_learned.md` exists, read it and identify any lessons
   relevant to this issue's domain.
3. Investigate the codebase to understand root cause. The bug may live in:
   - **`grammar.js`** — wrong rule, wrong precedence, ambiguous alternative,
     missing field name.
   - **`src/scanner.c`** — external scanner mishandling of an edge case
     (`_concat`, `_immediate`, EOF inside a braced word, etc.).
   - **`queries/irules/*.scm`** — wrong capture, wrong node type, broken
     `#match?` regex.
   - **`bindings/<lang>/`** — symbol mismatch, missing scanner in build
     inputs, version drift across language wrappers.
   - **`test/corpus/*.txt`** or **`test/highlight/*.tcl`** — false-pass test
     that masked the real bug.

   For grammar-vs-scanner ambiguity: confirm whether the bug is in the
   declarative rules (fix `grammar.js`) or the hand-written tokenizer (fix
   `scanner.c`). `tree-sitter generate` does NOT rewrite `scanner.c`, so its
   `tree_sitter_irules_external_scanner_*` symbols stay stable across
   regenerations.

4. **Check for the same bug pattern across sibling bindings.** The
   `bindings/<lang>/` wrappers deliberately mirror each other. If you fix a
   build input or symbol issue in one binding, check whether the same fix is
   needed in the C, Go, Node, Python, Rust, and Swift bindings.
5. **Plan the fix using sequential thinking.** Use the
   `sequential-thinking:sequentialthinking` MCP tool to reason through the
   resolution step by step before writing any code. The sequential thinking
   process MUST:
   - **Start** with `thoughtNumber: 1`, an initial `totalThoughts` estimate
     (typically 5-8), and `nextThoughtNeeded: true`.
   - **Analyze** the root cause — not just the symptom. For grammar bugs,
     trace which rule the parser actually selects and why. For scanner bugs,
     identify the exact lookahead state where the wrong token is emitted.
   - **Enumerate approaches** and evaluate trade-offs (simplicity,
     correctness, AST-shape stability). Remember `tree-sitter-irules` is
     consumed by editors and tooling — AST-shape changes (renamed nodes,
     removed fields, changed children) are breaking changes that affect
     every downstream query.
   - **Identify edge cases** — empty input, deeply-nested braces, escaped
     braces (`\{`, `\}`), comments inside `when` event bodies, namespace
     commands at unusual positions (lhs of `set`, inside `expr`), mixed
     line endings, non-ASCII strings, backslash line continuations, nested
     command substitution `[…[…]…]`.
   - **Cross-check against project rules** — confirm conventions in
     `AGENTS.md`. iRules is a strict superset of TCL syntactically; nothing
     legal in TCL should regress. Run the inherited TCL corpus tests when
     extending the grammar.
   - **Verify completeness** — confirm the plan covers implementation,
     corpus and/or highlight tests, and any required regeneration of
     `src/parser.c`.
   - **Conclude** with `nextThoughtNeeded: false` and a final plan summary.
   - Adjust `totalThoughts` up or down as understanding evolves. Use
     `isRevision` if earlier reasoning needs correction.
6. **Implement the fix.** Execute the plan from step 5. After every
   `grammar.js` edit, regenerate:

   ```bash
   npx tree-sitter generate
   ```

   `tree-sitter generate` rewrites `src/parser.c`, `src/grammar.json`, and
   `src/node-types.json`. Stage these alongside `grammar.js` — never commit
   the source change without the generated outputs.

   Do NOT bump tree-sitter grammar pins or `tree-sitter-cli` version as
   part of an issue fix; those are deliberate, separate changes.

7. Self-review the implementation:
   - Correctness: root cause addressed, not just symptom?
   - AST-shape stability: did you rename a node, remove a field, or change
     which children appear? If so, this is a breaking change — confirm the
     issue actually wanted that. Otherwise, find a non-breaking alternative.
   - Simplicity: simplest fix that solves the problem?
   - Completeness: edge cases handled? Sibling bindings updated if applicable?
     Queries updated if AST shape moved?
   - Test coverage: regression test added that would catch the exact bug if
     reintroduced? Includes field names in the expected AST?
   - Conventions: no comments unless the *why* is non-obvious; no
     hand-edits to generated files (`src/parser.c`, `src/grammar.json`,
     `src/node-types.json`).
8. Fix any issues found in self-review. If fixes were non-trivial, re-review.
9. **Write tests.** Sufficient testing is mandatory before proceeding. At
   minimum:
   - **Corpus test** under `test/corpus/` reproducing the bug input and
     pinning the correct AST. Include field names in the expected tree.
     Modify only the specific test that needs changing — never rewrite an
     entire corpus file to fix one test.
   - **Highlight test** under `test/highlight/` if the bug was query- or
     capture-related, with `; ^^^ @capture.name` assertions.
   - **Regression test** that would catch the exact bug if reintroduced.
   - For cross-binding fixes, add or update tests in **every** affected
     binding's test harness (`bindings/node/*_test.js`, `bindings/python/`,
     etc., as applicable).

   Tests must actually assert what they claim — no commented-out
   assertions, no missing field names where they would catch the bug, no
   tests that pass for the wrong reason.

10. **Update agent-local documentation.** Review and update each of the
    following as applicable:
    - `README.md` — if user-facing behavior, supported syntax, or install
      steps changed.
    - Doc comments inside `grammar.js` — only when the *why* of a precedence
      or rule choice is non-obvious.
    - Avoid hardcoding stale counts in any doc.
11. Do NOT update `CHANGELOG.md` — the orchestrator consolidates
    changelog entries after merging to avoid merge conflicts between
    parallel agents. Include the changelog entry text in your Phase 7
    result instead.

### Phase 2: Simplify

<!-- Adapted from the user-level /simplify skill -->

Review the diff (`git diff HEAD`) across three dimensions and apply fixes
directly:

**Reuse**:

- Repeated rule fragments in `grammar.js` that should be hoisted into a
  named choice (e.g., the iRules expr operators are already grouped — keep
  them grouped).
- Copy-pasted query patterns across `highlights.scm`, `folds.scm`,
  `indents.scm` that should share a capture name.
- Duplicate scanner helpers in `scanner.c` that can be consolidated.

**Clarity**:

- Ambiguous grammar alternatives the parser silently resolves with the
  wrong precedence — make precedence explicit (`prec`, `prec.left`,
  `prec.right`).
- Stringly-typed query captures where a more specific node type would do.
- `seq($.foo, optional($.bar), optional($.baz))` chains where a named
  helper rule would clarify intent.
- Rules that mix unrelated concerns; split or rename.
- Field names that no query consumes — either drop the field or wire it
  into a capture.

**Efficiency**:

- Unnecessary regex backtracking in `#match?` predicates — anchor with `^`
  / `$` or tighten character classes.
- Scratch scanner state, used only within a single `scan` call, that lives
  on the scanner struct instead of as a local. Do NOT demote state that must
  persist across calls — that state is serialized via the scanner's
  `serialize` / `deserialize` callbacks for incremental re-parses, and
  moving it to a local will silently break incremental editing.
- Corpus tests with redundant scaffolding that slow the test run.

Do NOT: extract tiny rules that obscure the grammar, simplify a clear
multi-line `seq` into an unreadable inline mess, or change AST shape just
to make the diff smaller.

Run `npx tree-sitter generate && npx tree-sitter test` to verify changes
parse and the corpus still passes after simplification.

### Phase 3: Review and Remediate

<!-- Adapted from /review (project-local) -- keep in sync -->

Review the cumulative diff (`git diff HEAD`) against this checklist. Read
each changed file in full for context.

**Correctness**:

- Off-by-one errors in scanner lookahead, regex anchors, corpus expected
  AST.
- Unreachable rule alternatives or dead branches after the change.
- Error cases silently swallowed (parser produces ERROR nodes the test
  ignores).
- Edge cases: empty input, single token, deeply-nested braces, escaped
  braces, comments inside event bodies, namespace commands at unusual
  positions, mixed line endings, non-ASCII strings.
- AST-shape change for existing callers — this is a breaking change for
  every downstream query. Confirm the issue actually wanted it.
- Cross-binding parity: was the fix mirrored across every sibling binding
  that needed it?
- TCL parity: iRules is a syntactic superset of TCL. Run a known-good TCL
  snippet (e.g., a representative `test/corpus/` inherited from
  `tree-sitter-tcl`) and confirm nothing regressed.

**Performance**:

- Catastrophic-backtracking regex in `#match?` predicates.
- Scanner branches that scan the full remaining input when a bounded
  lookahead would do.
- Generated `src/parser.c` size growth that suggests grammar bloat (if
  several MB larger after a small change, investigate).

**Security / robustness**:

- Scanner branches that index past the end of input without bounds check.
- Query patterns that crash the highlighter on malformed input.

**Tests**:

- Every new code path has a corresponding corpus or highlight test.
- Existing tests still cover their intended scenarios.
- Test assertions are specific (include field names, exact node types).
- Missing negative tests: the parser should NOT match `when` as a plain
  command name in a context that already has `when_event`, etc.
- Cross-binding fixes have a test in **every** affected binding harness.

For each finding, classify severity and effort:

- **bug** or **crash** -> fix immediately
- **performance** or **code-smell** (medium+ effort) -> fix if safe
- **trivial code-smell** or **test-gap** -> fix if trivial, note otherwise

Fix all actionable findings. If fixes were non-trivial, re-review the new
diff. Do NOT proceed with known bugs or crashes.

### Phase 4: Validate

```bash
npx tree-sitter generate
npx tree-sitter test
npm run lint
```

If any check fails on code you changed, fix and retry (one attempt).
If it fails again or fails on code you did not change, report as FAILED.

### Phase 5: Commit

Before committing, verify you are still on your agent branch:

```bash
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" != "$AGENT_BRANCH" ]; then
  echo "ERROR: Branch drift detected. Expected $AGENT_BRANCH, on $CURRENT_BRANCH"
  git checkout -- .
  git reset HEAD
  # Report FAILED
fi
```

Verify what will be staged:

```bash
git status
git diff HEAD --stat
```

Stage only files you intentionally changed (do NOT use `git add -A`):

```bash
git add <file1> <file2> ...
```

When `grammar.js` changed, stage it together with the regenerated
`src/parser.c`, `src/grammar.json`, and `src/node-types.json` in a single
commit. Never split the source edit and the regenerated outputs across
separate commits.

Commit with a Conventional Commits message that references the issue for
auto-close on push. Allowed types and scopes are listed in `AGENTS.md`
(`fix(grammar)`, `fix(scanner)`, `fix(queries)`, `fix(bindings/<lang>)`,
`fix(tests)`, etc.). The `Fixes #N` trailer goes in the **body**, not the
subject:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>

<body explaining what and why, 72-char lines>

Fixes #<ISSUE_NUMBER>
EOF
)"
```

Subject is imperative, lowercase, no trailing period, ≤ 72 chars. Do NOT
add `Co-Authored-By` lines unless explicitly requested.

Record the branch name, commit hash, and what changed:

```bash
git rev-parse --abbrev-ref HEAD
git rev-parse --short HEAD
git show --stat HEAD
```

### Phase 6: Annotate GitHub Issue

Update the GitHub issue with research findings and fix details. Do NOT
close the issue -- the `Fixes #N` commit trailer handles closure on merge.

Update BOTH the issue body AND add a comment. Use `--body-file` with a
temp file to avoid quoting issues:

```bash
cat > /tmp/issue-comment-<ISSUE_NUMBER>.md <<'COMMENT_EOF'
## Fix Summary

**Root cause**: <what was wrong and why>

**Changes**:
- <file>: <what changed>
- ...

**Bindings affected**: <list, or "n/a">

**Tests**: <what corpus / highlight test coverage was added>

**Commit**: <hash> on branch <branch-name>

<any additional notes, follow-up items, or related issues>
COMMENT_EOF
gh issue comment <ISSUE_NUMBER> --body-file /tmp/issue-comment-<ISSUE_NUMBER>.md
```

Also update the issue body to reflect the fix status:

```bash
gh issue view <ISSUE_NUMBER> --json body --jq '.body' > /tmp/issue-body-<ISSUE_NUMBER>.md
cat >> /tmp/issue-body-<ISSUE_NUMBER>.md <<'BODY_EOF'

---

## Resolution

**Status**: Fixed (pending merge)
**Commit**: <hash> on branch <branch-name>
**Root cause**: <brief summary>
BODY_EOF
gh issue edit <ISSUE_NUMBER> --body-file /tmp/issue-body-<ISSUE_NUMBER>.md
```

### Phase 7: Report Result

Return EXACTLY one of:

**SUCCESS**:

```
STATUS: SUCCESS
BRANCH: <branch-name>
COMMIT: <short-hash>
FILES: <number of files changed>
SUMMARY: <one-line description of the fix>
CHANGELOG: <changelog entry text, e.g. "Fixed incorrect highlight capture for namespace commands">
LESSON: <hard-won, globally reusable lesson if any, or "none" — the orchestrator gathers all non-empty values in Step 5c and prints them in Step 7 for the user to review via /lessons-learned>
```

**SKIPPED** (issue is invalid, already fixed, or requires no code changes):

```
STATUS: SKIPPED
REASON: <why no changes were needed>
```

**FAILED**:

```
STATUS: FAILED
REASON: <what went wrong>
ATTEMPTED: <what was tried before failure>
```

On FAILED, ensure no uncommitted changes remain in tracked files:

```bash
git checkout -- .
git reset HEAD
```

Do NOT run `git clean -fd` -- the worktree runtime manages untracked files.

**END AGENT PROMPT**

---

## Guardrails

- Do NOT merge the integration branch into `main` -- leave for the user
- Do NOT close GitHub issues -- the `Fixes #N` trailer handles this on merge
- Do NOT use `git push --force` or any destructive git operations
- Do NOT delete worktrees -- only the Claude Code runtime may do that
- Do NOT skip the review phase -- every fix must be reviewed before commit
- Do NOT bump `tree-sitter-cli` or grammar dependency versions as part of an
  issue fix; version bumps are deliberate, separate changes
- Do NOT hand-edit `src/parser.c`, `src/grammar.json`, or `src/node-types.json`
  — they are build outputs of `npx tree-sitter generate`
- If a worktree agent cannot safely resolve an issue, it must report FAILED
- Parallel agents in the same wave MUST touch different areas -- same-area
  issues, cross-binding issues, and cross-area issues are always serialized
  across waves
- Each worktree agent is fully self-contained -- it does not call
  /fix-issue, /simplify, or /review as skills. The logic is embedded in
  the prompt.
