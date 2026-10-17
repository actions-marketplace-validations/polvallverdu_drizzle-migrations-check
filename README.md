<div align="center">

# 🌧️ Drizzle Migrations Check

**Fail CI when your [Drizzle ORM](https://orm.drizzle.team) schema changes without a migration.**

[![Test](https://github.com/polvallverdu/drizzle-migrations-check/actions/workflows/test.yml/badge.svg)](https://github.com/polvallverdu/drizzle-migrations-check/actions/workflows/test.yml)
[![Marketplace](https://img.shields.io/badge/marketplace-drizzle--migrations--check-blue?logo=github)](https://github.com/marketplace/actions/drizzle-migrations-check)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

</div>

You edited `schema.ts`, opened a PR, and forgot to run `drizzle-kit generate`. Production
deploys, the migration never runs, and the app queries a column that doesn't exist.

This action catches that in CI. For each drizzle config it:

1. runs **`drizzle-kit check`** to make sure the migration history is consistent (no colliding migrations after a merge),
2. runs **`drizzle-kit generate`** and **fails if it produced any file**, printing the SQL that's missing,
3. also fails if drizzle-kit **needs to ask about a rename**, which means a migration is missing too.

No database needed. Works with one config or many, in a single repo or a monorepo.

```yaml
- uses: polvallverdu/drizzle-migrations-check@v1
```

---

## Contents

- [Quick start](#quick-start)
- [Usage](#usage)
  - [Single repo, single config](#single-repo-single-config)
  - [Multiple configs](#multiple-configs)
  - [Monorepo with several packages](#monorepo-with-several-packages)
  - [One package in a monorepo](#one-package-in-a-monorepo)
  - [Globs](#globs)
  - [pnpm, Yarn, Bun](#package-managers)
  - [Using the result in later steps](#using-the-result-in-later-steps)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [What a failure looks like](#what-a-failure-looks-like)
- [FAQ](#faq)
- [Let your coding agent set it up](#let-your-coding-agent-set-it-up)

## Quick start

```yaml
# .github/workflows/drizzle.yml
name: Drizzle

on: [pull_request]

jobs:
  migrations:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - uses: polvallverdu/drizzle-migrations-check@v1
```

The action calls `drizzle-kit` from your project, so **install your dependencies first**.

## Usage

### Single repo, single config

If your config is `drizzle.config.ts` at the repo root, you don't need any inputs:

```yaml
- uses: polvallverdu/drizzle-migrations-check@v1
```

If it lives somewhere else, point to it:

```yaml
- uses: polvallverdu/drizzle-migrations-check@v1
  with:
    configs: src/db/drizzle.config.ts
```

### Multiple configs

One config per line. Each config is checked on its own, and every failing one is reported (the action doesn't stop at the first failure).

```yaml
- uses: polvallverdu/drizzle-migrations-check@v1
  with:
    configs: |
      drizzle.users.config.ts
      drizzle.billing.config.ts
      drizzle.analytics.config.ts
```

Blank lines and lines starting with `#` are ignored.

### Monorepo with several packages

List configs from different packages, all relative to the repo root:

```text
.
├── pnpm-workspace.yaml
└── packages
    ├── db
    │   ├── drizzle.users.config.ts
    │   ├── drizzle.billing.config.ts
    │   └── drizzle.analytics.config.ts
    └── api
        └── drizzle.config.ts
```

```yaml
- uses: pnpm/action-setup@v6
- uses: actions/setup-node@v7
  with:
    node-version: 22
    cache: pnpm
- run: pnpm install --frozen-lockfile

- uses: polvallverdu/drizzle-migrations-check@v1
  with:
    runner: pnpm exec
    configs: |
      packages/db/drizzle.users.config.ts
      packages/db/drizzle.billing.config.ts
      packages/db/drizzle.analytics.config.ts
      packages/api/drizzle.config.ts
```

drizzle-kit runs **from each config's own directory** (`packages/db`, `packages/api`). That way the
`schema` and `out` paths in each config resolve the same way they do when you run
`drizzle-kit generate` inside the package, and `pnpm exec` finds that package's own `drizzle-kit`.

### One package in a monorepo

Use `working-directory` so config paths are relative to the package:

```yaml
- uses: polvallverdu/drizzle-migrations-check@v1
  with:
    working-directory: packages/api
    runner: pnpm exec
```

You can also give each package its own job, so they show up as separate checks:

```yaml
strategy:
  matrix:
    package: [db, api]
steps:
  # ...checkout + install...
  - uses: polvallverdu/drizzle-migrations-check@v1
    with:
      working-directory: packages/${{ matrix.package }}
      runner: pnpm exec
      configs: drizzle*.config.ts
```

### Globs

Globs work, so configs added later are picked up automatically:

```yaml
- uses: polvallverdu/drizzle-migrations-check@v1
  with:
    runner: pnpm exec
    configs: |
      packages/*/drizzle*.config.ts
      apps/**/drizzle.config.ts
```

If a glob matches nothing, the check fails, so a typo can't turn the check into a silent no-op.

### Package managers

`runner` is the command placed before `drizzle-kit`:

| Package manager | `runner` |
| --- | --- |
| npm | `npx` *(default)* |
| pnpm | `pnpm exec` |
| Yarn | `yarn` |
| Bun | `bunx` |

### Using the result in later steps

```yaml
- id: drizzle
  uses: polvallverdu/drizzle-migrations-check@v1
  continue-on-error: true

- if: steps.drizzle.outcome == 'failure'
  run: |
    echo "These configs need a migration:"
    echo "${{ steps.drizzle.outputs.failed-configs }}"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `configs` | `drizzle.config.ts` | Config paths or globs, one per line, relative to `working-directory`. |
| `runner` | `npx` | Command used to invoke drizzle-kit (`npx`, `pnpm exec`, `yarn`, `bunx`, …). |
| `working-directory` | `.` | Base directory that config paths are resolved from. |
| `run-in-config-dir` | `true` | Run drizzle-kit from each config's directory. Set to `false` if your config's `schema`/`out` paths are relative to `working-directory` rather than to the config file. |
| `check` | `true` | Also run `drizzle-kit check` to catch inconsistent migration history. |

## Outputs

| Output | Description |
| --- | --- |
| `failed-configs` | Configs that failed, one per line. Empty when everything is up to date. |

## What a failure looks like

Each failing config gets an error annotation on the PR, a collapsible log with the exact SQL
that is missing, and a row in the job summary:

```text
❌ packages/db/drizzle.billing.config.ts — Schema has changes without a migration.

+ALTER TABLE "invoices" ADD COLUMN "extra" text;
```

| Config | Status |
| --- | --- |
| `packages/db/drizzle.users.config.ts` | ✅ up to date |
| `packages/db/drizzle.billing.config.ts` | ❌ missing migration |
| `packages/db/drizzle.analytics.config.ts` | ✅ up to date |
| `packages/api/drizzle.config.ts` | ✅ up to date |

The possible statuses are:

| Status | Meaning | Fix |
| --- | --- | --- |
| ❌ missing migration | `drizzle-kit generate` produced new files | Run `drizzle-kit generate` and commit |
| ❌ missing migration (rename) | drizzle-kit needs to ask whether a column/table was renamed | Run `drizzle-kit generate` locally, answer the prompt, commit |
| ❌ check failed | Config couldn't be loaded, or migrations collide (e.g. two branches both added `0005_*`) | Regenerate the conflicting migration on top of the other branch |
| ❌ generate failed | drizzle-kit errored | See the log |
| ❌ not found | Config path or glob doesn't exist | Fix the path |

## FAQ

<details>
<summary><b>Does it need a database?</b></summary>

No. `drizzle-kit generate` and `drizzle-kit check` only compare your schema files against the
snapshots in your migrations folder.
</details>

<details>
<summary><b>Does it modify my repo?</b></summary>

It runs `drizzle-kit generate` in the runner's workspace, so when the check fails the generated
files are left there (handy if you want to upload them as an artifact). Nothing is committed or
pushed.
</details>

<details>
<summary><b>How does it detect changes?</b></summary>

It compares `git status` before and after `drizzle-kit generate`, including untracked files, so it
works even when the migrations folder is brand new. Other uncommitted files in the workspace don't
affect the result.
</details>

<details>
<summary><b>Does it work on macOS and Windows runners?</b></summary>

It's tested on `ubuntu-latest` and `macos-latest`. On Windows it should work under Git Bash, but that isn't tested.
</details>

## Let your coding agent set it up

This repo includes an [agent skill](skills/setup-drizzle-migrations-check/SKILL.md) that teaches
Claude Code (and other agents that support `SKILL.md`) how to add this check to a repo. The agent
finds your drizzle configs, works out your package manager and monorepo layout, writes the
workflow, and checks that your schema is currently up to date.

```bash
# with the skills CLI
npx skills add polvallverdu/drizzle-migrations-check

# or copy it into a project by hand
mkdir -p .claude/skills && cp -R skills/setup-drizzle-migrations-check .claude/skills/
```

Then ask: *"set up drizzle migrations check in CI"*.

## Development

```bash
cd test
npm install
npm test            # all scenarios
bash run.sh mono    # only scenarios whose name contains "mono"
```

The tests build throwaway git repos from [`test/fixtures`](test/fixtures) (a single-package repo
and a pnpm monorepo with a 3-config package and a single-config package). They cover up-to-date
schemas, drift, renames, colliding migrations, globs, `working-directory`, missing configs and
broken configs. CI also runs the action end to end with real npm and pnpm installs.

## Contributing

Issues and PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how the tests work and how
releases are made.

## License

[MIT](LICENSE)
