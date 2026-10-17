#!/usr/bin/env bash
# Builds a real, installed repo from a fixture for the e2e workflow:
#   e2e-setup.sh <fixture> <dest> <runner> <install command> <config>...
# It installs dependencies, generates the baseline migrations with <runner> and commits everything.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

fixture="$1" dest="$2" runner="$3" install="$4"
shift 4

new_repo "$fixture" "$dest"
echo node_modules > "$dest/.gitignore"
(cd "$dest" && $install)
DRIZZLE_KIT="$runner drizzle-kit" generate "$dest" "$@"
commit_all "$dest" "baseline migrations"
git -C "$dest" log --oneline
git -C "$dest" ls-files
