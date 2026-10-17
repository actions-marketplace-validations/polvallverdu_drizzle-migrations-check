#!/usr/bin/env bash
# Scenario tests for check.sh. Each test builds a throwaway git repo from a fixture
# under test/.work, puts it in some state, runs check.sh and asserts on the result.
#
#   cd test && npm install && bash run.sh [name-filter]
set -uo pipefail

source "$(dirname "$0")/lib.sh"

export PATH="$TEST_DIR/node_modules/.bin:$PATH"
export DRIZZLE_KIT=drizzle-kit
# `env drizzle-kit ...` resolves drizzle-kit from PATH, standing in for npx/pnpm exec.
export RUNNER=env

MONO_CONFIGS="packages/db/drizzle.users.config.ts
packages/db/drizzle.billing.config.ts
packages/db/drizzle.analytics.config.ts
packages/api/drizzle.config.ts"

passed=0
failed=0
failures=()

# run_check <repo> [VAR=value ...]: runs check.sh in <repo>, storing exit code and output.
run_check() {
  local repo="$1"; shift
  OUT_FILE="$WORK_DIR/$CURRENT.out"
  GH_OUTPUT="$WORK_DIR/$CURRENT.github_output"
  GH_SUMMARY="$WORK_DIR/$CURRENT.summary"
  : > "$GH_OUTPUT"; : > "$GH_SUMMARY"
  (cd "$repo" && env GITHUB_OUTPUT="$GH_OUTPUT" GITHUB_STEP_SUMMARY="$GH_SUMMARY" "$@" bash "$ROOT_DIR/check.sh") > "$OUT_FILE" 2>&1
  EXIT=$?
}

fail() { echo "    ✗ $*"; TEST_OK=false; }
expect_pass() { [ "$EXIT" -eq 0 ] || fail "expected success, got exit $EXIT"; }
expect_fail() { [ "$EXIT" -ne 0 ] || fail "expected failure, got exit 0"; }
expect_output() { grep -qF -- "$1" "$OUT_FILE" || fail "output missing: $1"; }
expect_summary() { grep -qF -- "$1" "$GH_SUMMARY" || fail "summary missing: $1"; }
# expect_failed_configs <line>...: exact list in the failed-configs output.
expect_failed_configs() {
  local actual expected
  actual=$(sed -e '1d' -e '$d' "$GH_OUTPUT" | sed '/^$/d')
  expected=$(printf '%s\n' "$@" | sed '/^$/d')
  [ "$actual" = "$expected" ] || fail "failed-configs was [$(echo $actual)], expected [$(echo $expected)]"
}

# ---------------------------------------------------------------- single repo

test_single_up_to_date() {
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  run_check "$R"
  expect_pass
  expect_output "drizzle.config.ts is up to date"
  expect_summary "| \`drizzle.config.ts\` | ✅ up to date |"
  expect_failed_configs
}

test_single_schema_drift() {
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  drift "$R/src/db/schema.ts"
  run_check "$R"
  expect_fail
  expect_output "Schema for drizzle.config.ts has changes without a migration"
  expect_output 'ADD COLUMN "extra" text'
  expect_failed_configs drizzle.config.ts
}

test_single_no_migrations_yet() {
  new_repo single-repo "$R"
  run_check "$R"
  expect_fail
  expect_output "CREATE TABLE \"users\""
  expect_failed_configs drizzle.config.ts
}

test_single_rename_needs_prompt() {
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  rename_column "$R/src/db/schema.ts" email email_address
  run_check "$R"
  expect_fail
  expect_output "drizzle-kit needs to ask whether something was renamed"
  expect_summary "missing migration (rename)"
}

test_single_migrations_not_committed_yet() {
  # The whole migrations folder is untracked: a new file inside it must still be detected.
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts
  run_check "$R"
  expect_pass
  drift "$R/src/db/schema.ts"
  run_check "$R"
  expect_fail
  expect_failed_configs drizzle.config.ts
}

test_single_unrelated_changes_ignored() {
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  echo "dirty" > "$R/notes.txt"
  echo "// edited" >> "$R/src/db/schema.ts"
  run_check "$R"
  expect_pass
}

test_single_colliding_migrations() {
  # Two branches each add migration 0001; after merging both, `drizzle-kit check` must fail.
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  local snap
  sed -i.bak 's|// @drift|a: text("a"),|' "$R/src/db/schema.ts" && rm "$R/src/db/schema.ts.bak"
  generate "$R" drizzle.config.ts
  snap=$(cat "$R"/drizzle/meta/0001_snapshot.json)
  git -C "$R" checkout -q -- . && git -C "$R" clean -fdq
  sed -i.bak 's|// @drift|b: text("b"),|' "$R/src/db/schema.ts" && rm "$R/src/db/schema.ts.bak"
  generate "$R" drizzle.config.ts
  printf '%s\n' "$snap" > "$R/drizzle/meta/0002_snapshot.json"
  commit_all "$R" "merge both branches"

  run_check "$R"
  expect_fail
  expect_output "which is a collision"
  expect_summary "check failed"

  # Without the check, generate still refuses to run on top of the broken history.
  run_check "$R" RUN_CHECK=false
  expect_fail
  expect_summary "generate failed"
}

test_single_config_outside_root_run_from_root() {
  # Config in a subfolder with paths relative to the repo root -> run-in-config-dir: false.
  new_repo single-repo "$R"
  mkdir -p "$R/config" && mv "$R/drizzle.config.ts" "$R/config/drizzle.config.ts"
  generate "$R" drizzle.config.ts 2>/dev/null # no-op: config moved
  (cd "$R" && drizzle-kit generate --config config/drizzle.config.ts >/dev/null) && commit_all "$R" migrations
  run_check "$R" CONFIGS=config/drizzle.config.ts RUN_IN_CONFIG_DIR=false
  expect_pass
  drift "$R/src/db/schema.ts"
  run_check "$R" CONFIGS=config/drizzle.config.ts RUN_IN_CONFIG_DIR=false
  expect_fail
  expect_failed_configs config/drizzle.config.ts
}

test_single_broken_config() {
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  echo "this is not typescript (" >> "$R/drizzle.config.ts"
  run_check "$R"
  expect_fail
  expect_output 'Expected ";"'
  expect_summary "check failed"
  run_check "$R" RUN_CHECK=false
  expect_fail
  expect_summary "generate failed"
}

test_missing_config_file() {
  new_repo single-repo "$R" && generate "$R" drizzle.config.ts && commit_all "$R" migrations
  run_check "$R" CONFIGS="drizzle.config.ts
does/not/exist.config.ts"
  expect_fail
  expect_output "does/not/exist.config.ts (file not found)"
  expect_summary "| \`drizzle.config.ts\` | ✅ up to date |"
}

test_not_a_git_repo() {
  local dir
  dir=$(mktemp -d)
  cp -R "$TEST_DIR/fixtures/single-repo/." "$dir"
  run_check "$dir"
  rm -rf "$dir"
  expect_fail
  expect_output "is not inside a git repository"
}

# ---------------------------------------------------------------- monorepo

mono_baseline() {
  new_repo monorepo "$R" && generate "$R" $MONO_CONFIGS && commit_all "$R" migrations
}

test_mono_all_up_to_date() {
  mono_baseline
  run_check "$R" CONFIGS="$MONO_CONFIGS"
  expect_pass
  expect_output "All 4 drizzle config(s) are up to date."
  expect_failed_configs
}

test_mono_drift_in_one_of_three_configs() {
  mono_baseline
  drift "$R/packages/db/src/billing/schema.ts"
  run_check "$R" CONFIGS="$MONO_CONFIGS"
  expect_fail
  expect_output 'ALTER TABLE "invoices" ADD COLUMN "extra" text'
  expect_failed_configs packages/db/drizzle.billing.config.ts
  expect_summary "| \`packages/db/drizzle.users.config.ts\` | ✅ up to date |"
  expect_summary "| \`packages/db/drizzle.analytics.config.ts\` | ✅ up to date |"
  expect_summary "| \`packages/api/drizzle.config.ts\` | ✅ up to date |"
}

test_mono_drift_in_single_config_package() {
  mono_baseline
  drift "$R/packages/api/src/schema.ts"
  run_check "$R" CONFIGS="$MONO_CONFIGS"
  expect_fail
  expect_failed_configs packages/api/drizzle.config.ts
}

test_mono_drift_in_two_packages() {
  mono_baseline
  drift "$R/packages/db/src/users/schema.ts"
  drift "$R/packages/api/src/schema.ts"
  run_check "$R" CONFIGS="$MONO_CONFIGS"
  expect_fail
  expect_failed_configs packages/db/drizzle.users.config.ts packages/api/drizzle.config.ts
}

test_mono_glob() {
  mono_baseline
  run_check "$R" CONFIGS="packages/*/drizzle*.config.ts"
  expect_pass
  expect_output "All 4 drizzle config(s) are up to date."
  drift "$R/packages/db/src/analytics/schema.ts"
  run_check "$R" CONFIGS="packages/*/drizzle*.config.ts"
  expect_fail
  expect_failed_configs packages/db/drizzle.analytics.config.ts
}

test_mono_glob_matches_nothing() {
  mono_baseline
  run_check "$R" CONFIGS="apps/*/drizzle.config.ts"
  expect_fail
  expect_output "apps/*/drizzle.config.ts (glob matched nothing)"
}

test_mono_working_directory_single_package() {
  mono_baseline
  local cfgs="drizzle.users.config.ts
drizzle.billing.config.ts
drizzle.analytics.config.ts"
  run_check "$R" WORKING_DIRECTORY=packages/db CONFIGS="$cfgs"
  expect_pass
  expect_output "All 3 drizzle config(s) are up to date."
  drift "$R/packages/db/src/users/schema.ts"
  run_check "$R" WORKING_DIRECTORY=packages/db CONFIGS="$cfgs"
  expect_fail
  expect_failed_configs drizzle.users.config.ts
}

test_mono_comments_and_blank_lines() {
  mono_baseline
  run_check "$R" CONFIGS="
  # database package
  packages/db/drizzle.users.config.ts

  packages/api/drizzle.config.ts
"
  expect_pass
  expect_output "All 2 drizzle config(s) are up to date."
}

# ---------------------------------------------------------------- runner

mkdir -p "$WORK_DIR"
for t in $(declare -F | awk '{print $3}' | grep '^test_' | grep -- "${1:-}"); do
  CURRENT="${t#test_}"
  R="$WORK_DIR/$CURRENT"
  TEST_OK=true
  echo "• $CURRENT"
  "$t"
  if $TEST_OK; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failures+=("$CURRENT")
    echo "    --- check.sh output ($OUT_FILE) ---"
    sed 's/^/    | /' "$OUT_FILE" | tail -40
  fi
done

echo
echo "$passed passed, $failed failed"
if [ $failed -gt 0 ]; then
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
