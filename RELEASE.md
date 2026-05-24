# Release runbook

This document covers the one-time setup and per-release procedure for
publishing `tree-sitter-irules` to crates.io, npm, and PyPI via the
automated [`release.yml`](.github/workflows/release.yml) workflow.

## One-time setup

The workflow uses OIDC Trusted Publishing on all three registries —
no long-lived `NPM_TOKEN`, `CARGO_REGISTRY_TOKEN`, or
`PYPI_API_TOKEN` is stored on the repo. Before the first release,
register a trusted publisher claim on each registry and create the
matching `release` GitHub environment.

### GitHub environment

Create an environment named `release` on the repo settings page
(Settings → Environments → New environment). The three publish jobs
(`crates-publish`, `npm-publish`, `pypi-publish`) bind to this name
via `environment: release` so each registry's trusted-publisher claim
can require it. Optional but recommended: add a required reviewer or
a deployment branch rule restricting `release` to `v*` tag refs.

### crates.io trusted publisher

1. Visit `https://crates.io/settings/profile` and add a new GitHub
   trusted publisher.
2. Owner: `dekobon`. Repository: `tree-sitter-irules`. Workflow:
   `release.yml`. Environment: `release`.
3. **First-release caveat**: crates.io does not accept pending
   trusted-publisher claims for crates that do not yet exist on the
   registry. Bootstrap by manually `cargo publish`ing once from a
   local workstation (with a personal API token, generated at
   `https://crates.io/settings/tokens`), then add the trusted
   publisher and yank the bootstrap version:

   ```bash
   cargo login                       # paste the personal token
   cargo publish --locked            # one-time bootstrap
   cargo yank --version <X.Y.Z>      # immediately yank
   cargo logout                      # revoke the local token
   ```

   Subsequent releases land via the trusted publisher; the yanked
   bootstrap version remains in the index for audit but is hidden
   from `cargo` consumers.

### npm trusted publisher

1. Visit `https://www.npmjs.com/settings/<your-username>/packages` (or
   the package settings page once it exists).
2. Add a GitHub Actions trusted publisher with the same claims as
   crates.io: owner `dekobon`, repository `tree-sitter-irules`,
   workflow `release.yml`, environment `release`.
3. npm CLI ≥ 11.5.1 is required for OIDC publish; the workflow's
   `npm-publish` job verifies this floor on every run.

### PyPI trusted publisher

1. Visit `https://pypi.org/manage/account/publishing/`.
2. Add a publisher for project `tree-sitter-irules` with owner
   `dekobon`, repository `tree-sitter-irules`, workflow `release.yml`,
   environment `release`.
3. PyPI **does** support pending trusted publishers for projects that
   do not yet exist — no bootstrap upload required.

### Package-name collisions

The `validate` job hardcodes `expected_npm="tree-sitter-irules"`,
`expected_crate="tree-sitter-irules"`, and
`expected_pypi="tree-sitter-irules"`. If any of the three returns a
name-already-taken error during the first publish, choose a
scoped/prefixed alternative (e.g. `@dekobon/tree-sitter-irules` on
npm, `dekobon-tree-sitter-irules` on crates.io and PyPI) and update
**all of these in the same commit**:

1. `package.json` `name` (and re-run `npm install --package-lock-only`
   to refresh `package-lock.json`)
2. `Cargo.toml` `[package].name`
3. `pyproject.toml` `[project].name`
4. `release.yml` `expected_npm`, `expected_crate`, `expected_pypi`
5. `crates-publish` job's `INDEX` URL (sparse-index sharding is
   based on the canonical name)

## Per-release procedure

```bash
# 1. Ensure parser artifacts are regenerated and committed.
npx tree-sitter generate
git diff --exit-code src/parser.c src/grammar.json src/node-types.json
# (no output means clean; if dirty, commit before continuing)

# 2. Bump the version in all four metadata files in one commit.
make version                  # prompts for the version, updates
                              # package.json, Cargo.toml, pyproject.toml,
                              # tree-sitter.json

# 3. Update CHANGELOG.md.
#    Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a
#    fresh empty `## [Unreleased]` above it, and add the link
#    footer:
#      [Unreleased]: https://github.com/dekobon/tree-sitter-irules/compare/vX.Y.Z...HEAD
#      [X.Y.Z]:      https://github.com/dekobon/tree-sitter-irules/releases/tag/vX.Y.Z

# 4. Commit and push.
git add -A
git commit -m "chore: release vX.Y.Z"
git push origin main

# 5. Tag and push the tag.
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z
```

The tag push triggers `.github/workflows/release.yml`:

1. `validate` — checks tag is SemVer 2, version matches all four
   metadata files, package names match expected, CHANGELOG has a
   `## [X.Y.Z]` section.
2. `test` — multi-OS parser tests; also fails if committed parser
   artifacts have drifted from `grammar.js`.
3. `crates-publish`, `npm-prebuilds`/`npm-publish`,
   `pypi-wheels`/`pypi-sdist`/`pypi-publish` — run in parallel.
   Each is idempotent: re-running the same tag short-circuits any
   publish whose version is already on the registry.
4. `github-release` — extracts the matching CHANGELOG section and
   creates the GitHub Release via `gh release create --verify-tag`.

## Recovering from a partial publish

If the workflow fails after one or two registries have already
accepted the upload, re-trigger from the same tag:

```bash
gh workflow run release.yml --ref vX.Y.Z
```

- `crates-publish` queries the sparse index and skips if the version
  is already present.
- `pypi-publish` uses `skip-existing: true` and no-ops on files PyPI
  already has.
- `npm-publish` will fail if the version is already on the registry;
  bump to the next patch and re-tag rather than overwriting.

## Yanking a release

```bash
cargo yank --version X.Y.Z              # crates.io
npm deprecate "tree-sitter-irules@X.Y.Z" "<reason>"   # npm
# PyPI: yank via the web UI at
# https://pypi.org/manage/project/tree-sitter-irules/releases/
```

Yanking does not delete the artifact; consumers with `=X.Y.Z` pins
can still resolve. Bump and publish a fix.
