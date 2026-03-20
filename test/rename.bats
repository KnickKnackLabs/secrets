#!/usr/bin/env bats
# Tests for delete and rename operations across both providers.
# Uses mock binaries — no real keychain or 1Password interaction.

load helpers

# ============================================================
# Keychain: delete + rename
# ============================================================

setup() {
  setup_test_env
  create_mock_security
  create_mock_op
}

# --- keychain_delete ---

@test "keychain_delete removes a stored secret" {
  source "$LIB_DIR/keychain.sh"
  seed_keychain "test-agent" "github-pat" "my-token"

  run keychain_delete "test-agent" "github-pat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted:"* ]]

  # Verify it's gone
  run keychain_get "test-agent" "github-pat"
  [ "$status" -ne 0 ]
}

@test "keychain_delete fails for nonexistent key" {
  source "$LIB_DIR/keychain.sh"

  run keychain_delete "test-agent" "nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "keychain_delete does not affect other keys" {
  source "$LIB_DIR/keychain.sh"
  seed_keychain "test-agent" "key-a" "value-a"
  seed_keychain "test-agent" "key-b" "value-b"

  keychain_delete "test-agent" "key-a"

  # key-b should still be there
  run keychain_get "test-agent" "key-b"
  [ "$status" -eq 0 ]
  [ "$output" = "value-b" ]
}

@test "keychain_delete does not affect other agents" {
  source "$LIB_DIR/keychain.sh"
  seed_keychain "alice" "github-pat" "alice-token"
  seed_keychain "bob" "github-pat" "bob-token"

  keychain_delete "alice" "github-pat"

  # Bob's key should still be there
  run keychain_get "bob" "github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "bob-token" ]
}

# --- keychain_rename ---

@test "keychain_rename moves value to new key" {
  source "$LIB_DIR/keychain.sh"
  seed_keychain "test-agent" "old-key" "my-secret"

  run keychain_rename "test-agent" "old-key" "new-key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Renamed:"* ]]

  # New key has the value
  run keychain_get "test-agent" "new-key"
  [ "$status" -eq 0 ]
  [ "$output" = "my-secret" ]

  # Old key is gone
  run keychain_get "test-agent" "old-key"
  [ "$status" -ne 0 ]
}

@test "keychain_rename preserves multi-line values" {
  source "$LIB_DIR/keychain.sh"
  local multiline="line1
line2
line3"
  seed_keychain "test-agent" "old-key" "$multiline"

  keychain_rename "test-agent" "old-key" "new-key"

  run keychain_get "test-agent" "new-key"
  [ "$status" -eq 0 ]
  [ "$output" = "$multiline" ]
}

@test "keychain_rename fails when old key does not exist" {
  source "$LIB_DIR/keychain.sh"

  run keychain_rename "test-agent" "nonexistent" "new-key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "keychain_rename fails when old and new key are the same" {
  source "$LIB_DIR/keychain.sh"
  seed_keychain "test-agent" "same-key" "value"

  run keychain_rename "test-agent" "same-key" "same-key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"same"* ]]
}

@test "keychain_rename overwrites existing new key" {
  source "$LIB_DIR/keychain.sh"
  seed_keychain "test-agent" "old-key" "correct-value"
  seed_keychain "test-agent" "new-key" "stale-value"

  keychain_rename "test-agent" "old-key" "new-key"

  run keychain_get "test-agent" "new-key"
  [ "$status" -eq 0 ]
  [ "$output" = "correct-value" ]

  # Old key is gone
  run keychain_get "test-agent" "old-key"
  [ "$status" -ne 0 ]
}

# ============================================================
# 1Password: delete + rename
# ============================================================

# --- op_delete ---

@test "op_delete removes a stored secret" {
  source "$LIB_DIR/1password.sh"
  seed_op "test-agent" "github-pat" "my-token"

  run op_delete "test-agent" "github-pat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted:"* ]]

  # Verify it's gone
  run op_get "test-agent" "github-pat"
  [ "$status" -ne 0 ]
}

@test "op_delete fails for nonexistent key" {
  source "$LIB_DIR/1password.sh"

  run op_delete "test-agent" "nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "op_delete does not affect other keys" {
  source "$LIB_DIR/1password.sh"
  seed_op "test-agent" "key-a" "value-a"
  seed_op "test-agent" "key-b" "value-b"

  op_delete "test-agent" "key-a"

  # key-b should still be there
  run op_get "test-agent" "key-b"
  [ "$status" -eq 0 ]
  [ "$output" = "value-b" ]
}

@test "op_delete does not affect other agents" {
  source "$LIB_DIR/1password.sh"
  seed_op "alice" "github-pat" "alice-token"
  seed_op "bob" "github-pat" "bob-token"

  op_delete "alice" "github-pat"

  # Bob's key should still be there
  run op_get "bob" "github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "bob-token" ]
}

# --- op_rename ---

@test "op_rename moves value to new key" {
  source "$LIB_DIR/1password.sh"
  seed_op "test-agent" "old-key" "my-secret"

  run op_rename "test-agent" "old-key" "new-key"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Renamed:"* ]]

  # New key has the value
  run op_get "test-agent" "new-key"
  [ "$status" -eq 0 ]
  [ "$output" = "my-secret" ]

  # Old key is gone
  run op_get "test-agent" "old-key"
  [ "$status" -ne 0 ]
}

@test "op_rename fails when old key does not exist" {
  source "$LIB_DIR/1password.sh"

  run op_rename "test-agent" "nonexistent" "new-key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "op_rename fails when old and new key are the same" {
  source "$LIB_DIR/1password.sh"
  seed_op "test-agent" "same-key" "value"

  run op_rename "test-agent" "same-key" "same-key"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"same"* ]]
}

@test "op_rename overwrites existing new key" {
  source "$LIB_DIR/1password.sh"
  seed_op "test-agent" "old-key" "correct-value"
  seed_op "test-agent" "new-key" "stale-value"

  op_rename "test-agent" "old-key" "new-key"

  run op_get "test-agent" "new-key"
  [ "$status" -eq 0 ]
  [ "$output" = "correct-value" ]

  # Old key is gone
  run op_get "test-agent" "old-key"
  [ "$status" -ne 0 ]
}
