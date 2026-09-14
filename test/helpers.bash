#!/usr/bin/env bash
# Test helpers for secrets BATS tests.
#
# Loads all helper modules: setup, mocks, seed functions, tool wrapper.
# Tests just `load helpers` to get everything.
#
# Resolve from the test checkout, not an inherited Mise activation context.
export REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export LIB_DIR="$REPO_DIR/lib"

HELPERS_DIR="$REPO_DIR/test/helpers"

source "$HELPERS_DIR/setup.bash"
source "$HELPERS_DIR/mock-security.bash"
source "$HELPERS_DIR/mock-op.bash"
