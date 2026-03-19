#!/usr/bin/env bats
# Tests for the 1Password provider (lib/1password.sh).
# Uses a mock op binary — no real 1Password interaction.

load helpers

setup() {
  setup_test_env
  create_mock_op
  source "$LIB_DIR/secret-keys.sh"
  source "$LIB_DIR/1password.sh"
}

# --- op_get ---

@test "op_get retrieves a stored value" {
  seed_op "test-agent" "github-pat" "my-pat-token"

  run op_get "test-agent" "github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "my-pat-token" ]
}

@test "op_get fails for nonexistent item" {
  run op_get "test-agent" "github-pat"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"not found"* ]]
}

@test "op_get fails for unknown key name" {
  run op_get "test-agent" "nonexistent-key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown key"* ]]
}

@test "op_get resolves correct 1Password item for gpg keys" {
  seed_op "test-agent" "gpg-private-key" "-----BEGIN PGP PRIVATE KEY-----"

  run op_get "test-agent" "gpg-private-key"
  [ "$status" -eq 0 ]
  [ "$output" = "-----BEGIN PGP PRIVATE KEY-----" ]
}

@test "op_get isolates agents" {
  seed_op "alice" "github-pat" "alice-token"
  seed_op "bob" "github-pat" "bob-token"

  run op_get "alice" "github-pat"
  [ "$output" = "alice-token" ]

  run op_get "bob" "github-pat"
  [ "$output" = "bob-token" ]
}

# --- op_set ---

@test "op_set creates a new item" {
  run op_set "test-agent" "github-pat" "new-token"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stored:"* ]]

  # Verify it's retrievable
  run op_get "test-agent" "github-pat"
  [ "$output" = "new-token" ]
}

@test "op_set updates an existing item" {
  op_set "test-agent" "github-pat" "old-token"
  op_set "test-agent" "github-pat" "new-token"

  run op_get "test-agent" "github-pat"
  [ "$output" = "new-token" ]
}

@test "op_set reads from stdin when no value argument" {
  echo -n "stdin-token" | op_set "test-agent" "email-password"

  run op_get "test-agent" "email-password"
  [ "$status" -eq 0 ]
  [ "$output" = "stdin-token" ]
}

@test "op_set fails on empty value" {
  run op_set "test-agent" "github-pat" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "op_set fails for unknown key name" {
  run op_set "test-agent" "nonexistent-key" "some-value"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown key"* ]]
}

# --- roundtrip ---

@test "roundtrip: set then get returns original value" {
  op_set "test-agent" "matrix-password" "s3cr3t!"

  run op_get "test-agent" "matrix-password"
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t!" ]
}

# --- vault configuration ---

@test "uses SECRETS_1PASSWORD_VAULT for vault name" {
  export SECRETS_1PASSWORD_VAULT="Custom-Vault"
  # Re-source to pick up
  source "$LIB_DIR/1password.sh"

  op_set "test-agent" "github-pat" "vault-test"

  # Check the file is stored under the custom vault
  [ -f "$MOCK_OP_STORE/Custom-Vault/test-agent - GitHub/PAT" ]
}
