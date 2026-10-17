---
name: setup-drizzle-migrations-check
description: Add a GitHub Actions check that fails CI when a Drizzle ORM schema changes without a migration, using polvallverdu/drizzle-migrations-check. Use when the user wants to verify Drizzle migrations in CI, catch a forgotten `drizzle-kit generate`, or add a drizzle schema/migration check to a single repo or a monorepo with one or more drizzle configs.
---

# Set up Drizzle Migrations Check

[`polvallverdu/drizzle-migrations-check`](https://github.com/polvallverdu/drizzle-migrations-check)
runs `drizzle-kit check` and `drizzle-kit generate` for each drizzle config. It fails if
generate would create files, or if drizzle-kit would have to ask about a rename. It needs no
database. It only needs the repo checked out and dependencies installed.

## 1. Inspect the repo

Collect these facts before writing anything:

1. **Drizzle configs.** Find every config, skipping `node_modules`:
   ```bash
   git ls-files | grep -E '(^|/)drizzle[^/]*\.config\.(ts|js|mjs|cjs|mts)$'
   ```
   If none are found, ask the user. Don't guess. Open each config and note its `schema` and `out`.
2. **Package manager**, from the lockfile at the repo root:
   | Lockfile | Install | `runner` | Setup |
   | --- | --- | --- | --- |
   | `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | `pnpm exec` | `pnpm/action-setup@v6` before `actions/setup-node` |
   | `package-lock.json` | `npm ci` | `npx` (default, omit it) | — |
   | `yarn.lock` | `yarn install --immutable` (Berry) or `yarn install --frozen-lockfile` (v1) | `yarn` | — |
   | `bun.lock` / `bun.lockb` | `bun install --frozen-lockfile` | `bunx` | `oven-sh/setup-bun@v2` |
3. **Monorepo or not.** Look for `pnpm-workspace.yaml`, `workspaces` in the root `package.json`,
   `turbo.json` or `nx.json`. Note which packages own the configs.
4. **Node version.** Use `.nvmrc`, `.node-version`, `engines.node` or `packageManager`, in that
   order. Fall back to `22`.
5. **Existing workflows.** Look in `.github/workflows/`. If there is already a CI workflow that
   checks out and installs dependencies on pull requests, add a step to it instead of making a
   new file.
6. **Path base.** Do the config's `schema`/`out` paths start from the config's folder or from
   somewhere else? The action runs drizzle-kit **from each config's own folder** by default.
   That's correct when the paths are written relative to the config file, which is the usual
   case, including in monorepos. If the user normally runs `drizzle-kit generate --config sub/dir/drizzle.config.ts`
   from the repo root and the paths start from the root, set `run-in-config-dir: false`.

## 2. Choose the `configs` input

- Only `./drizzle.config.ts` at the root: leave `configs` out.
- A single config somewhere else: `configs: path/to/drizzle.config.ts`.
- Several configs: list them one per line, relative to the repo root (or to `working-directory`).
- Many packages, or packages that change often: a glob such as `packages/*/drizzle*.config.ts`.
  A glob that matches nothing fails the check, so check it with `ls <glob>` first.
- Checking just one package: set `working-directory: packages/<name>` and keep `configs`
  relative to that folder.

## 3. Write the workflow

Pin the action to `@v1`. Template for a new `.github/workflows/drizzle-migrations.yml`. Adjust the
setup and install steps to the package manager:

```yaml
name: Drizzle migrations

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  drizzle-migrations:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      # pnpm only:
      - uses: pnpm/action-setup@v6
      - uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: pnpm # or npm / yarn
      - run: pnpm install --frozen-lockfile
      - uses: polvallverdu/drizzle-migrations-check@v1
        with:
          runner: pnpm exec
          configs: |
            packages/db/drizzle.users.config.ts
            packages/db/drizzle.billing.config.ts
            packages/api/drizzle.config.ts
```

Notes:
- Keep the default branch name the repo actually uses (`main`, `master`, …).
- If the configs read env vars at load time (e.g. `process.env.DATABASE_URL!` in `dbCredentials`), `generate`
  and `check` don't connect to a database, but a config that throws when a variable is missing
  will still fail. Add a placeholder under `env:` on the step, e.g.
  `DATABASE_URL: postgres://placeholder@localhost/placeholder`, and don't add a real secret.
- In a monorepo, a full install is usually needed. With pnpm you can narrow it to the packages
  with configs: `pnpm install --frozen-lockfile --filter <pkg>...`.

## 4. Verify locally

Before finishing, run the same check the action will run, from each config's folder:

```bash
cd <config dir> && <runner> drizzle-kit check --config <config file>
cd <config dir> && <runner> drizzle-kit generate --config <config file>
git status --porcelain --untracked-files=all
```

- If `generate` creates files, the repo **already** has a schema change with no migration, and the new
  check would fail on its first run. Tell the user and show them the generated SQL. Don't commit
  migrations unless they ask. Revert the generated files with `git checkout -- <out> && git clean -fd <out>`.
- If drizzle-kit asks about a rename, also stop and tell the user.
- If the config fails to load, fix that (or the `env:` placeholders) before going on.

## 5. Report back

Tell the user:
- which file you created or edited, and which configs it checks,
- that a failing PR will show an error note per config and a summary table,
- that you can add `continue-on-error: true` plus the `failed-configs` output if they want
  something to happen after a failure (e.g. a PR comment).

## Inputs reference

| Input | Default | Meaning |
| --- | --- | --- |
| `configs` | `drizzle.config.ts` | Config paths or globs, one per line, relative to `working-directory`. Lines starting with `#` are ignored. |
| `runner` | `npx` | Command placed before `drizzle-kit`. |
| `working-directory` | `.` | Folder that config paths start from. |
| `run-in-config-dir` | `true` | Run drizzle-kit from each config's own folder. |
| `check` | `true` | Also run `drizzle-kit check`. |

Output `failed-configs`: the configs that failed, one per line.
