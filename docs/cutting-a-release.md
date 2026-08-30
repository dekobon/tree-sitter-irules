# Cutting a release

This is the step-by-step procedure for releasing `tree-sitter-irules`.
`AGENTS.md` covers the day-to-day commit / changelog conventions; this
document is the walkthrough — what to do, in what order, and what to
check when something looks wrong.

The pipeline is defined in
[`.github/workflows/release.yml`](../.github/workflows/release.yml).
Everything downstream of `git push --tags` is automated.

## What the release pipeline does

One push of a `v*` tag runs this end-to-end:

1. **validate** — derives the version from the tag and checks parity
   against `tree-sitter.json` (`metadata.version`), `package.json`,
   `package-lock.json`, `Cargo.toml`, and `pyproject.toml`. Verifies
   the distribution names match the expected `tree-sitter-irules`
   strings on each registry. Greps `CHANGELOG.md` for a matching
   `## [x.y.z]` section.
2. **test** — runs `tree-sitter generate` and the corpus tests, plus
   the Rust binding tests, on Ubuntu, Windows, and macOS-14. The
   `tree-sitter-cli` ref is resolved from
   `package-lock.json` so the CI parser matches the committed
   `src/parser.c`.
3. **crates-publish** — authenticates to crates.io via
   [Trusted Publishing](https://crates.io/docs/trusted-publishing)
   (OIDC), then runs `cargo publish --locked` for
   `tree-sitter-irules`. The job queries the sparse index
   first and skips idempotently if the version is already on
   crates.io (so `workflow_dispatch` re-runs on the same tag don't
   error out on the duplicate upload).
4. **npm-prebuilds** — builds Node.js N-API prebuilds for Linux,
   macOS, and Windows via `prebuildify --napi --strip`, and uploads
   them as artefacts.
5. **npm-publish** — downloads every prebuild into `prebuilds/`,
   then runs `npm publish --provenance --access public` for
   `tree-sitter-irules`. The step first queries the registry and
   skips if that version is already on npm, so — like
   `crates-publish` and `pypi-publish` — re-runs on the same tag are
   idempotent. The package's `files` array ships the prebuilds, the
   WASM blob, the queries, the bindings, and the generated parser
   source.
6. **pypi-wheels** / **pypi-sdist** — builds abi3 wheels via
   `cibuildwheel` on each OS and an sdist via `python -m build
   --sdist`.
7. **pypi-publish** — gathers wheels + sdist into `dist/` and
   publishes `tree-sitter-irules` to PyPI via
   `pypa/gh-action-pypi-publish` (Trusted Publishing).
8. **github-release** — runs after crates/npm/PyPI publish succeed.
   Extracts the matching `## [x.y.z]` section from `CHANGELOG.md`
   with an `awk` script and creates the GitHub Release via
   `gh release create --verify-tag`.

If any stage fails, nothing downstream runs. `crates-publish`,
`npm-publish`, `pypi-publish`, and `github-release` are the only
jobs that mutate anything outside this repo.

## Prerequisites (one-time setup)

You only need to do this once per project, but verify each item
before your first real release.

### Repository secrets and OIDC

| Mechanism | Used by | Notes |
|-----------|---------|-------|
| crates.io Trusted Publishing | `crates-publish` | No repo secret. The `auth` step exchanges the GitHub OIDC token for a short-lived `CARGO_REGISTRY_TOKEN`. |
| PyPI Trusted Publishing | `pypi-publish` | No repo secret. `pypa/gh-action-pypi-publish` performs the OIDC exchange. |
| npm Trusted Publishing | `npm-publish` | No repo secret. npm CLI >= 11.5.1 auto-detects the runner's OIDC environment and exchanges the GitHub ID token for a short-lived registry token. `--provenance` is set so npm records the SLSA attestation alongside. |

All three publish jobs are pinned to the `release` GitHub
Environment so the OIDC `environment` claim is bound. The
environment must exist and (optionally) carry protection rules
before the first release runs.

If the crates.io, npm, or PyPI trusted-publisher entry is
missing or its claims don't match (owner, repo, workflow
filename, environment), the corresponding publish step fails
fast with an explicit claims-mismatch / OIDC error.

### crates.io Trusted Publisher setup

1. **Create a `release` GitHub Environment.** Repo
   **Settings → Environments → New environment**, name it exactly
   `release`. The publish jobs reference this environment and the
   crates.io trusted publisher matches the `environment` OIDC claim
   against it.
2. **Bootstrap the crate on crates.io** (only required before the
   very first release; skip if `tree-sitter-irules` already
   exists on crates.io). Unlike npm and PyPI, crates.io does not
   yet support **pending** trusted publishers — the crate must
   exist before a TP entry can be registered against it. From a
   clean checkout at the release-prep commit:

   ```bash
   cargo login                                              # short-lived API token from crates.io/settings/tokens
   cargo publish -p tree-sitter-irules --locked
   curl -fsSL https://index.crates.io/tr/ee/tree-sitter-irules \
     | grep '"vers":"0.1.0"'                                # confirm the upload landed
   ```

   The `crates-publish` job in `release.yml` is idempotent — it
   queries the sparse index and skips if the version is already
   present — so the same v0.1.0 tag can run the workflow afterwards
   without a duplicate-upload error.
3. **Register a Trusted Publisher on crates.io.** Once the crate
   exists, open the settings page for `tree-sitter-irules`
   and add a GitHub publisher with:

   - Repository owner: `dekobon`
   - Repository name: `tree-sitter-irules`
   - Workflow filename: `release.yml` (basename only)
   - Environment: `release`

   After this entry is registered, the automated `crates-publish`
   job takes over and the manual bootstrap is never needed again.

If `rust-lang/crates-io-auth-action` cuts a new release, re-resolve
the commit SHA and update both the pin and the trailing `# vX.Y.Z`
comment in `.github/workflows/release.yml`. Never float to a tag.

### PyPI Trusted Publisher setup

On `pypi.org`, open the project settings for
`tree-sitter-irules` (or the **pending publisher** page if
the project doesn't exist yet) and add a GitHub publisher with:

- Owner: `dekobon`
- Repository: `tree-sitter-irules`
- Workflow filename: `release.yml`
- Environment: `release`

A pending publisher is the right choice for the very first PyPI
upload — it lets the OIDC exchange succeed before the project
exists on PyPI.

### npm Trusted Publisher setup

Unlike PyPI, **npm does not support pending trusted publishers** —
the package must exist on the registry before a TP entry can be
registered against it. The very first publish therefore needs the
same kind of manual bootstrap that crates.io does. After that
single upload, all subsequent releases go through the automated
TP pipeline.

1. **Bootstrap the package on npm** (only required before the
   very first release; skip if `tree-sitter-irules`
   already exists on npm). `tree-sitter-irules` is an **unscoped**
   package, so the bootstrap publishes it under the npm account
   that will own it. From a clean checkout at the release-prep
   commit, on a machine where `npm whoami` resolves to that account.

   **Gotcha**: if the account has 2FA enabled (recommended), the
   publish below needs a fresh one-time code (`--otp=<code>`). If
   you just changed account permissions or logged in elsewhere, run
   a fresh `npm login` first — stale tokens can 404 with "you do not
   have permission" even when the website shows the account as
   authorized.

   ```bash
   # Build prebuilds. If you have access to the prior failed CI
   # run, prefer downloading its `prebuilds-*` artifacts so the
   # bootstrap ships the full linux-x64 / darwin-arm64 / win32-x64
   # set rather than just your local platform:
   gh run download <run-id> --dir /tmp/prebuilds --pattern 'prebuilds-*'
   mkdir -p prebuilds
   cp -r /tmp/prebuilds/prebuilds-*/* prebuilds/

   # Confirm the package set:
   npm pack --dry-run

   # Publish. `--otp=<6-digit-code>` is required only if the
   # account enforces 2FA for write actions; omit the flag
   # otherwise. Supply a fresh code from your authenticator app.
   # Skip `--provenance` — provenance requires CI OIDC and isn't
   # available from a local terminal. The first automated release
   # post-bootstrap will carry provenance.
   npm publish --access public --otp=<6-digit-code>

   # Clean up:
   rm -rf prebuilds/ /tmp/prebuilds
   ```

2. **Register the Trusted Publisher on the now-existing package.**
   On `npmjs.com`, navigate to
   **https://www.npmjs.com/package/tree-sitter-irules/access**
   → **Trusted Publisher** section → **GitHub Actions** → fill in:

   - Organization or user: `dekobon`
   - Repository: `tree-sitter-irules`
   - Workflow filename: `release.yml`
   - Environment: `release`

   All fields are case-sensitive and must match the OIDC claims
   exactly.

3. After this, the automated `npm-publish` job authenticates via
   OIDC for every subsequent release — no token, no OTP, no human
   in the loop. The manual bootstrap is never needed again unless
   the package is unpublished and re-created.

The `npm-publish` job uses Node 24, which ships with npm 11.x
natively — Trusted Publishing requires npm >= 11.5.1, and Node 22
runners only ship npm 10.x, so Node 24 avoids a brittle self-upgrade
step. Bump the `node-version` floor deliberately when npm 12 lands.
No `NPM_TOKEN` secret is needed once the bootstrap is done — the
OIDC exchange is automatic.

### Distribution names

The unscoped `tree-sitter-irules` name is currently free on every
flat registry, so each ecosystem uses the same unscoped name:

| Registry | Name |
|----------|------|
| npm | `tree-sitter-irules` |
| crates.io | `tree-sitter-irules` |
| PyPI | `tree-sitter-irules` |
| Go module | `github.com/dekobon/tree-sitter-irules` (URL-namespaced) |
| Swift package | identified by Git URL |
| C library | `libtree-sitter-irules` (no naming conflict) |

The `validate` job hard-fails if any of `package.json`,
`package-lock.json`, `Cargo.toml`, or `pyproject.toml` drifts from
the expected name above. A partial rename would publish under the
wrong name on one registry and either fail (collision) or squat on
a new name, so the check is intentionally noisy.

If the first publish to any registry returns a name-already-taken
error, switch to a scoped/prefixed alternative (e.g.
`@dekobon/tree-sitter-irules` on npm,
`dekobon-tree-sitter-irules` on crates.io and PyPI) and update
**all of these in the same commit**: `package.json` `name` (then
re-run `npm install --package-lock-only`), `Cargo.toml`
`[package].name`, `pyproject.toml` `[project].name`, the
`expected_npm` / `expected_crate` / `expected_pypi` values in
`release.yml`, and the `crates-publish` job's sparse-index `INDEX`
URL (the shard path is derived from the canonical crate name).

The Go module path, the Swift package URL, and the `libtree-sitter-irules`
C library name are **convention only** — `validate` does not check
them. Renaming `bindings/go/go.mod`, the Swift `Package.swift`
identifier, or the C library name will not fail CI, so verify
those manually if you rename the repo or fork.

Go and Swift consumers fetch the source directly from the tagged
Git ref; there is no separate publish step for them. The
`validate → test` chain still runs on every tag, so a broken Go
or Swift binding fails the release before downstream users see it.

## Bumping the version

The release pipeline is strict about version parity: the `validate`
job rejects the tag if it does not match every one of
`tree-sitter.json`, `package.json`, `Cargo.toml`, and
`pyproject.toml`. Bump the version deliberately, in one commit,
before tagging.

`tree-sitter.json` → `metadata.version` is the canonical source.
`npx tree-sitter version <X.Y.Z>` (wrapped by `make version`)
updates all four files in one go:

```bash
make version    # prompts for the new version, runs tree-sitter version <X.Y.Z>
```

After that, regenerate the lockfile and the parser source:

```bash
npm install --package-lock-only    # picks up the new version in package-lock.json
npx tree-sitter generate           # regenerates src/parser.c, etc.
make test                          # corpus + highlight tests still pass
npm run lint
```

The committed `src/parser.c` must be generated by the same
`tree-sitter-cli` version that CI uses. CI resolves the version
from `package-lock.json` (`packages["node_modules/tree-sitter-cli"].version`)
and pins `tree-sitter/setup-action/cli@v2` to that exact tag.
Always regenerate `src/parser.c` with the locally-installed CLI
(`npx tree-sitter generate`) — never with a globally-installed
one that may be a different version — and commit the lockfile,
`tree-sitter.json`, and `parser.c` together.

Pick the version per SemVer, using the AGENTS.md "is this
breaking?" rules:

- **Major**: AST shape change (rename / remove a node, remove a
  field, change which children appear), removed or renamed query
  capture, or a binding's public symbol / module name / function
  signature changes.
- **Minor**: new grammar rule, new optional field, new query
  capture, or a new binding without touching existing surface.
- **Patch**: parsing bug fix, query bug fix, or binding bug fix
  with no AST shape, capture, or symbol change.

## Pre-release checklist

Before tagging, on `main`:

- [ ] All intended changes are merged and CI is green.
- [ ] Version bumped via `make version` — `tree-sitter.json`,
      `package.json`, `Cargo.toml`, `pyproject.toml` all show the
      new value, and `package-lock.json` has been regenerated.
- [ ] `src/parser.c`, `src/grammar.json`, `src/node-types.json`
      have been regenerated with the locally-installed
      `tree-sitter-cli` and committed.
- [ ] `make test` is clean.
- [ ] `npm run lint` is clean.
- [ ] If `bindings/rust/**` or `Cargo.toml` changed: `cargo clippy
      --all-targets -- -D warnings` and `cargo test` are clean.
- [ ] `CHANGELOG.md` has a `## [x.y.z] - YYYY-MM-DD` section with
      the release notes. The header must match the tag exactly,
      minus the leading `v`. Move entries out of `## [Unreleased]`
      into the new section and leave a fresh empty `## [Unreleased]`
      above it.
- [ ] Distribution names still match what `validate` expects (only
      relevant if you renamed packages — usually a no-op).

Commit the version bump, the regenerated parser, and the
changelog move together so the release-prep commit is a single,
self-contained change:

```text
chore(release): prepare v0.1.0
```

## Cutting a stable release

Pick a SemVer version (e.g. `0.1.0`). The tag is the version
prefixed with `v`.

```bash
# From a clean main checkout at the release-prep commit:
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

That's it — the push of the tag triggers `release.yml`. Watch it
in the Actions tab:

```bash
gh run watch
# or
gh run list --workflow=Release
```

The Windows and macOS prebuild / wheel jobs are the slowest
stages; first runs after a CLI bump tend to be slower because the
generate + test step is uncached. Plan on tens of minutes rather
than a tight window.

## Cutting a pre-release

The `validate` regex
(`^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`)
accepts SemVer 2 pre-release suffixes — e.g. `v0.1.0-rc1`,
`v0.1.0-beta.2`, `v0.1.0-alpha3`. The version in every metadata
file must include the suffix exactly.

There is **no automatic skip** of registry uploads for pre-release
tags in this pipeline. If you
push `v0.1.0-rc1`, the pipeline will try to publish to crates.io,
npm, and PyPI. crates.io and PyPI uploads are **irrevocable**; an
`-rc` upload squats on that version forever.

**Recommended: gate the publish jobs before doing any rehearsal.**
Add a `prerelease` output to `validate` (set to `true` when the
tag has a suffix) and an
`if: needs.validate.outputs.prerelease != 'true'` guard to each
of `crates-publish`, `npm-publish`, and `pypi-publish`. This
makes `-rc` / `-beta`
tags a safe rehearsal channel that still exercises `validate`,
`test`, and the prebuild / wheel / sdist matrix.

Until that gate exists, the options are:

1. **Re-run an existing tag**: requires a `workflow_dispatch:`
   trigger; the current `release.yml` is push-only, so add a
   `workflow_dispatch:` line under `on:` before relying on this.
2. **Dry run in a fork**: create a throwaway tag in a fork that
   has no Trusted Publisher registrations on any of the three
   registries. The publish steps fail fast on auth, but
   `validate`, `test`, `npm-prebuilds`, `pypi-wheels`, and
   `pypi-sdist` exercise the full build matrix.
3. **Burn-a-version pre-release**: bump the metadata to the
   suffixed version, ensure `CHANGELOG.md` has the matching
   section, tag, and push. Be aware crates.io yank and PyPI
   delete are scoped operations (the version stays reserved) —
   re-uploading the same version is not possible.

## Monitoring a live release

While the workflow runs:

```bash
gh run list --workflow=Release --limit 1
gh run view --log-failed   # on any failure
```

Common failure signatures and what they mean:

| Failure | Cause |
|---------|-------|
| `Tag 'vX' is not a valid SemVer 2 version` | The tag isn't SemVer 2; re-tag. |
| `Version mismatch: tag=… tree-sitter.json=…` | One of the four metadata files drifted. Re-run `make version` and commit. |
| `package-lock.json name is …, expected …` | Run `npm install --package-lock-only` and commit. |
| `CHANGELOG.md is missing a section for X.Y.Z` | Add a `## [X.Y.Z]` heading on the tagged commit. Editing `main` after tagging does not help — re-tag. |
| `tree-sitter test` failures in `test` job | The committed `src/parser.c` was generated by a different CLI version. Regenerate locally with `npx tree-sitter generate`. |
| crates.io `auth` step claims mismatch | Trusted publisher on crates.io was registered against the wrong owner / repo / workflow / environment. |
| PyPI `gh-action-pypi-publish` 4xx | Pending publisher not registered, or the project name on PyPI is owned by a different publisher. |
| `npm publish` OIDC / 4xx | Trusted publisher on npmjs.com missing, or its claims (owner, repo, workflow, environment) don't match the runner. Verify the entry on the package's trusted publisher page. |
| `npm publish` "npm CLI does not support trusted publishing" | The runner's npm is older than 11.5.1. The `Install npm with Trusted Publishing support` step in `npm-publish` should prevent this; if it surfaces, the step's `npm@^11.5.1` pin regressed or its version guard was removed. |
| `Empty release notes for X.Y.Z` | The `## [X.Y.Z]` heading exists but has no body. Add content under it. |

## Post-release verification

The `github-release` job creates the Release with the extracted
changelog section; check it renders correctly on
`https://github.com/dekobon/tree-sitter-irules/releases/tag/vX.Y.Z`.

Verify each registry caught the upload and that the GitHub Release
rendered the changelog correctly:

```bash
TAG=v0.1.0
VERSION=0.1.0

# GitHub Release — confirms `github-release` ran and the changelog
# section was extracted into the release body.
gh release view "$TAG"

# npm
npm view "tree-sitter-irules@${VERSION}" version

# crates.io (sparse index — same query the publish job uses)
curl -fsSL "https://index.crates.io/tr/ee/tree-sitter-irules" \
  | grep "\"vers\":\"${VERSION}\""

# PyPI
curl -fsSL "https://pypi.org/pypi/tree-sitter-irules/${VERSION}/json" \
  | jq -r '.info.version'
```

Smoke-test a downstream install:

```bash
# Node
mkdir /tmp/ts-irules-check && cd /tmp/ts-irules-check
npm init -y >/dev/null
npm install "tree-sitter-irules@${VERSION}"
node -e 'const g = require("tree-sitter-irules");
         console.log(Object.keys(g), typeof g.language);'

# Rust
cargo new --lib ts-irules-check && cd ts-irules-check
cargo add "tree-sitter-irules@${VERSION}"
cargo build

# Python — install wheel-only first to confirm the wheel actually built
# and resolves on this platform; cibuildwheel is the bulk of the
# release work and an sdist-only install would mask a wheel regression.
python3 -m venv /tmp/ts-irules-check-py && source /tmp/ts-irules-check-py/bin/activate
pip install --only-binary=:all: "tree-sitter-irules==${VERSION}"
python3 -c 'import tree_sitter_irules as g; print(g.language())'
```

Go and Swift do not need verification beyond the tag being
present and the test job passing — they fetch from the Git ref.

## Fixing a broken release

The pipeline fails *before* publish on any validate or test error,
so a broken release almost never reaches users.

The three publish jobs (`crates-publish`, `npm-publish`,
`pypi-publish`) run in parallel — a failure in one does not abort
the others. Diagnosing a partial success therefore means looking
at each job independently.

Re-running the workflow on the same tag is supported via the
`workflow_dispatch:` trigger:

```bash
gh workflow run release.yml --ref vX.Y.Z
```

The `validate` job derives the version from `GITHUB_REF` under both
the push and dispatch triggers, so a re-run from a tag ref is
indistinguishable from a tag push for everything downstream. Only
dispatch from a *tag* ref — branch refs fail `validate` with a
"not a valid SemVer 2 version" error.

**Caveat**: GitHub Actions resolves the workflow file from the ref
being dispatched, not from `main`. `workflow_dispatch:` therefore
only works on tags whose ref commit includes the trigger — i.e.,
tags created *after* the commit that added `workflow_dispatch:` to
`release.yml`. For older tags lacking the trigger, the only
recourse is the tag-delete-and-re-push dance, or creating the
GitHub Release by hand.

The fix then depends on which job failed:

- **crates.io upload failed**: `crates-publish` is idempotent. It
  queries the sparse index and skips when the version is already
  present, so once the underlying issue is fixed, re-running the
  workflow uploads if needed and no-ops if not.
- **PyPI upload failed**: `pypi-publish` runs
  `pypa/gh-action-pypi-publish` with `skip-existing: true`, so the
  step no-ops on any file PyPI already has. A re-run after a
  partial upload completes the missing files without erroring on
  the duplicates.
- **npm upload failed**: `npm-publish` queries the registry and
  skips when the version is already present, so re-running the
  workflow on the same tag is idempotent — it uploads if the prior
  attempt never reached npm and no-ops if it did. (The guard exists
  because `npm publish` on its own rejects a duplicate version
  outright, which would fail the job and skip `github-release`.) If
  you instead need to *replace* an already-published artifact, `npm
  unpublish tree-sitter-irules@X.Y.Z` is allowed within 24 hours of
  upload; after that the version is immutable — bump to the next
  patch and re-tag.
- **`github-release` failed**: re-run via
  `gh workflow run release.yml --ref vX.Y.Z`, or create the release
  by hand with `gh release create vX.Y.Z --notes-file
  <(awk ...CHANGELOG.md)`.

If you need to pull a release entirely:

```bash
gh release delete vX.Y.Z --cleanup-tag --yes
# crates.io: cargo yank --version X.Y.Z (does NOT free the name)
# PyPI:      pip-side deletion via the web UI (does NOT free the name)
# npm:       npm unpublish tree-sitter-irules@X.Y.Z (within 24h)
```

Then fix the underlying issue, bump to `vX.Y.(Z+1)`, and re-tag.
**Do not re-use a published version number** — crates.io and PyPI
will refuse, and npm consumers may have already cached the old
artefacts even if you unpublished within the window.

## Known gaps

- **Pre-release tags are not gated.** Pushing `v0.1.0-rc1`
  publishes to crates.io / npm / PyPI just like a stable tag.
  If you need rehearsal without external uploads, use a fork or
  add a `prerelease`-aware `if:` to the publish jobs.
- **No WASM artefact on the Release.** `tree-sitter build --wasm`
  runs on `npm start` but is not built or uploaded by `release.yml`.
  Editor integrations that pull the WASM blob fetch it from the
  npm tarball instead.
- **No signature on the GitHub Release assets — intentionally.**
  The npm publish carries SLSA provenance via `--provenance`;
  crates.io and PyPI carry their own provenance via Trusted
  Publishing. Adding a minisign signature on the `github-release`
  job's tarball would require a long-lived signing key as a repo
  secret, weakening the otherwise-zero-secret posture without
  adding meaningful integrity guarantees beyond what the three
  registry attestations already provide. Consumers should pull
  from the named registries, not the GitHub release tarball, when
  integrity matters.
