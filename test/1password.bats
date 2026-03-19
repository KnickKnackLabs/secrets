#!/usr/bin/env bats
# Tests for the 1Password provider (lib/1password.sh).
# Uses a mock op binary — no real 1Password interaction.

load helpers

setup() {
  setup_test_env
  create_mock_op
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

@test "op_get uses flat naming convention (agent/key)" {
  seed_op "test-agent" "github-pat" "my-token"

  # Verify the flat naming in mock store
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  [ -f "$MOCK_OP_STORE/$vault/test-agent/github-pat/value" ]
}

@test "op_get retrieves gpg keys correctly" {
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

# --- name-agnostic: any key name works ---

@test "op accepts arbitrary key names" {
  op_set "test-agent" "my-custom-key" "custom-value"

  run op_get "test-agent" "my-custom-key"
  [ "$status" -eq 0 ]
  [ "$output" = "custom-value" ]
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

  # Check the file is stored under the custom vault with flat naming
  [ -f "$MOCK_OP_STORE/Custom-Vault/test-agent/github-pat/value" ]
}

# --- op_list (dynamic discovery) ---

@test "op_list discovers stored keys for an agent" {
  seed_op "test-agent" "github-pat" "token1"
  seed_op "test-agent" "email-password" "pass1"

  run op_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ email-password"* ]]
  [[ "$output" == *"✓ github-pat"* ]]
}

@test "op_list shows nothing for agent with no secrets" {
  run op_list "nobody"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no secrets found"* ]]
}

@test "op_list does not leak other agents' keys" {
  seed_op "alice" "github-pat" "alice-token"
  seed_op "bob" "email-password" "bob-pass"

  run op_list "alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ github-pat"* ]]
  [[ "$output" != *"email-password"* ]]
}

@test "op_list discovers arbitrary key names" {
  seed_op "test-agent" "my-custom-key" "val1"
  seed_op "test-agent" "another-thing" "val2"

  run op_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ another-thing"* ]]
  [[ "$output" == *"✓ my-custom-key"* ]]
}
