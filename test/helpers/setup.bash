#!/usr/bin/env bash
# Test environment setup and tool wrapper.

setup_test_env() {
  export TEST_DIR="$BATS_TEST_TMPDIR/secrets-test-$$"
  export MOCK_BIN="$TEST_DIR/mock-bin"
  export MOCK_KEYCHAIN="$TEST_DIR/keychain"
  export MOCK_OP_STORE="$TEST_DIR/op-store"
  export MOCK_LIBSECRET="$TEST_DIR/libsecret"
  mkdir -p "$MOCK_BIN" "$MOCK_KEYCHAIN" "$MOCK_OP_STORE" "$MOCK_LIBSECRET"

  # Use test-specific service prefix to avoid touching real keychain
  export SECRETS_SERVICE_PREFIX="test-secrets/"
  export SECRETS_KEYCHAIN_ACCOUNT="secrets"
  export SECRETS_LIBSECRET_ACCOUNT="secrets"

  # Point library at mock binaries
  export SECURITY="$MOCK_BIN/security"
  export SECRET_TOOL="$MOCK_BIN/secret-tool"
  export OP="$MOCK_BIN/op"
}

# Tool wrapper — call secrets tasks through mise, matching real usage.
# Usage: secrets get baby-joel/github-pat
secrets() {
  mise -C "$REPO_DIR" run -q "$@"
}
export -f secrets
