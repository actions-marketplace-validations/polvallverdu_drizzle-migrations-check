# Helpers shared by run.sh and the e2e workflow to build throwaway git repos from fixtures.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
WORK_DIR="${WORK_DIR:-$TEST_DIR/.work}"

# new_repo <fixture> <dest>: copy a fixture into <dest> and commit it as a fresh git repo.
new_repo() {
  local fixture="$1" dest="$2"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -R "$TEST_DIR/fixtures/$fixture" "$dest"
  git -C "$dest" init -q -b main
  git -C "$dest" config user.email test@example.com
  git -C "$dest" config user.name test
  git -C "$dest" add -A
  git -C "$dest" commit -qm "fixture: $fixture"
}

# generate <repo> <config>...: run drizzle-kit generate for each config, from the config's dir.
generate() {
  local repo="$1"; shift
  local cfg
  for cfg in "$@"; do
    (cd "$repo/$(dirname "$cfg")" && ${DRIZZLE_KIT:-npx drizzle-kit} generate --config "$(basename "$cfg")" >/dev/null) || return 1
  done
}

# commit_all <repo> <message>
commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
}

# drift <file>: add a column to a schema so it no longer matches its migrations.
drift() {
  sed -i.bak 's|// @drift|extra: text("extra"),|' "$1" && rm "$1.bak"
}

# rename_column <file> <from> <to>: rename a column's DB name (makes drizzle-kit ask "rename or create?").
rename_column() {
  sed -i.bak "s|\"$2\"|\"$3\"|" "$1" && rm "$1.bak"
}
