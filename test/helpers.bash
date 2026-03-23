#!/usr/bin/env bash
# Test helpers for secrets BATS tests.
#
# Loads all helper modules: setup, mocks, seed functions, tool wrapper.
# Tests just `load helpers` to get everything.
#
# Requires MISE_CONFIG_ROOT — run tests via `mise run test`, not `bats` directly.

if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "MISE_CONFIG_ROOT not set — run tests via: mise run test" >&2
  exit 1
fi

export REPO_DIR="$MISE_CONFIG_ROOT"
export LIB_DIR="$REPO_DIR/lib"

HELPERS_DIR="$REPO_DIR/test/helpers"

source "$HELPERS_DIR/setup.bash"
source "$HELPERS_DIR/mock-security.bash"
source "$HELPERS_DIR/mock-op.bash"
source "$HELPERS_DIR/mock-gpg.bash"
