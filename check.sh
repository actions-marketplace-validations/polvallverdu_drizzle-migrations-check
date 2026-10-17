#!/usr/bin/env bash
# Verifies that drizzle migrations are in sync with the schema for one or more
# drizzle configs. Driven by env vars so it can run outside of GitHub Actions:
#
#   CONFIGS            newline-separated config paths or globs (relative to WORKING_DIRECTORY)
#   RUNNER             command prefix used to invoke drizzle-kit (npx, pnpm exec, bunx, ...)
#   WORKING_DIRECTORY  base directory, defaults to "."
#   RUN_IN_CONFIG_DIR  "true" runs drizzle-kit from each config's directory (default)
#   RUN_CHECK          "true" also runs `drizzle-kit check` (default)
set -uo pipefail

CONFIGS="${CONFIGS:-drizzle.config.ts}"
RUNNER="${RUNNER:-npx}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"
RUN_IN_CONFIG_DIR="${RUN_IN_CONFIG_DIR:-true}"
RUN_CHECK="${RUN_CHECK:-true}"

GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

cd "$WORKING_DIRECTORY" 2>/dev/null || {
  echo "::error::working-directory '$WORKING_DIRECTORY' does not exist"
  exit 1
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "::error::'$WORKING_DIRECTORY' is not inside a git repository. Did you forget actions/checkout?"
  exit 1
fi

# -uall so a new file inside an already-untracked migrations folder still shows up.
snapshot() { git status --porcelain --untracked-files=all; }

# Expand each line of CONFIGS, resolving globs (including ** via globstar).
shopt -s nullglob
shopt -s globstar 2>/dev/null || true # bash >= 4
configs=()
missing=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -z "$line" ] && continue
  [[ "$line" == \#* ]] && continue
  if [[ "$line" == *[\*\?\[]* ]]; then
    IFS=$'\n'
    matches=($line)
    unset IFS
    [ -z "${matches+x}" ] && missing+=("$line (glob matched nothing)")
    configs+=("${matches[@]+"${matches[@]}"}")
  elif [ -f "$line" ]; then
    configs+=("$line")
  else
    missing+=("$line (file not found)")
  fi
done <<< "$CONFIGS"
shopt -u nullglob

failed=()
rows=()
for m in "${missing[@]+"${missing[@]}"}"; do
  echo "::error title=drizzle config not found::$m"
  failed+=("$m")
  rows+=("| \`$m\` | ❌ not found |")
done

if [ ${#configs[@]} -eq 0 ] && [ ${#missing[@]} -eq 0 ]; then
  echo "::error::No drizzle configs given."
  exit 1
fi

drizzle() {
  local cfg="$1"; shift
  if [ "$RUN_IN_CONFIG_DIR" = "true" ]; then
    (cd "$(dirname "$cfg")" && $RUNNER drizzle-kit "$@" --config "$(basename "$cfg")" </dev/null)
  else
    $RUNNER drizzle-kit "$@" --config "$cfg" </dev/null
  fi
}

for cfg in "${configs[@]+"${configs[@]}"}"; do
  echo "::group::drizzle-kit · $cfg"
  # Validate the migration history first: generate can't work on top of a broken one.
  if [ "$RUN_CHECK" = "true" ] && ! drizzle "$cfg" check; then
    echo "::endgroup::"
    echo "::error file=$cfg,title=drizzle-kit check failed::drizzle-kit check failed for $cfg. Either the config could not be loaded or the migration history is inconsistent (e.g. colliding migrations after merging two branches). See the log above."
    failed+=("$cfg")
    rows+=("| \`$cfg\` | ❌ check failed |")
    continue
  fi

  before=$(snapshot)

  out=$(drizzle "$cfg" generate 2>&1)
  code=$?
  printf '%s\n' "$out"

  # drizzle-kit exits 0 when it can't show a rename/create prompt without a TTY,
  # so look at the output too. Needing a prompt means a migration is missing.
  if grep -q "Interactive prompts require a TTY" <<< "$out"; then
    echo "::endgroup::"
    echo "::error file=$cfg,title=Missing drizzle migration::Schema for $cfg has changes without a migration (drizzle-kit needs to ask whether something was renamed). Run drizzle-kit generate locally and commit the result."
    failed+=("$cfg")
    rows+=("| \`$cfg\` | ❌ missing migration (rename) |")
    continue
  fi
  if [ $code -ne 0 ] || grep -q "^Error" <<< "$out"; then
    echo "::endgroup::"
    echo "::error file=$cfg,title=drizzle-kit generate failed::drizzle-kit generate failed for $cfg. Check the config and the log above."
    failed+=("$cfg")
    rows+=("| \`$cfg\` | ❌ generate failed |")
    continue
  fi

  after=$(snapshot)
  if [ "$after" != "$before" ]; then
    changed=$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$after" | sort))
    echo "Files changed by drizzle-kit generate:"
    printf '%s\n' "$changed"
    root=$(git rev-parse --show-toplevel)
    while IFS= read -r entry; do
      path="${entry:3}"
      if [[ "$entry" == "??"* ]]; then
        git -C "$root" --no-pager diff --no-index -- /dev/null "$path" || true
      else
        git -C "$root" --no-pager diff -- "$path"
      fi
    done <<< "$changed"
    echo "::endgroup::"
    echo "::error file=$cfg,title=Missing drizzle migration::Schema for $cfg has changes without a migration. Run drizzle-kit generate and commit the result."
    failed+=("$cfg")
    rows+=("| \`$cfg\` | ❌ missing migration |")
    continue
  fi

  echo "::endgroup::"
  echo "✅ $cfg is up to date"
  rows+=("| \`$cfg\` | ✅ up to date |")
done

{
  echo "### Drizzle migrations check"
  echo
  echo "| Config | Status |"
  echo "| --- | --- |"
  printf '%s\n' "${rows[@]}"
} >> "$GITHUB_STEP_SUMMARY"

{
  echo "failed-configs<<__DRIZZLE_EOF__"
  printf '%s\n' "${failed[@]+"${failed[@]}"}"
  echo "__DRIZZLE_EOF__"
} >> "$GITHUB_OUTPUT"

if [ ${#failed[@]} -gt 0 ]; then
  echo
  echo "Failed configs:"
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi

echo
echo "All ${#configs[@]} drizzle config(s) are up to date."
