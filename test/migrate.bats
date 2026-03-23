#!/usr/bin/env bats
# Tests for the migrate task (structured → flat 1Password naming).
# Uses mock op binary — no real 1Password interaction.

load helpers

MIGRATE_SCRIPT="$BATS_TEST_DIRNAME/../.mise/tasks/migrate"

setup() {
  setup_test_env
  create_mock_op
}

# Helper: run the migrate script with mock op and given agent
run_migrate() {
  local agent="$1" dry_run="${2:-false}"
  usage_agent="$agent" usage_dry_run="$dry_run" OP="$MOCK_BIN/op" \
    run bash "$MIGRATE_SCRIPT"
}

# --- Basic migration ---

@test "migrate converts legacy items to flat naming" {
  seed_op_legacy "ikma" "Identity" "passphrase" "SECRET_PASS"
  seed_op_legacy "ikma" "GPG" "Private Key" "-----BEGIN PGP PRIVATE KEY-----"
  seed_op_legacy "ikma" "Email" "password" "email-pass-123"

  run_migrate "ikma"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passphrase:"* ]]
  [[ "$output" == *"gpg-private-key:"* ]]
  [[ "$output" == *"email-password:"* ]]

  # Verify flat items were created
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  [ -f "$MOCK_OP_STORE/$vault/ikma/passphrase/value" ]
  [ -f "$MOCK_OP_STORE/$vault/ikma/gpg-private-key/value" ]
  [ -f "$MOCK_OP_STORE/$vault/ikma/email-password/value" ]

  # Verify values are correct
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/passphrase/value")" = "SECRET_PASS" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/gpg-private-key/value")" = "-----BEGIN PGP PRIVATE KEY-----" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/email-password/value")" = "email-pass-123" ]
}

@test "migrate preserves old items (non-destructive)" {
  seed_op_legacy "ikma" "Identity" "passphrase" "SECRET_PASS"

  run_migrate "ikma"
  [ "$status" -eq 0 ]

  # Old item still exists
  [ -f "$MOCK_OP_STORE/Agents/ikma - Identity/passphrase" ]
}

@test "migrate handles all legacy key mappings" {
  seed_op_legacy "ikma" "GitHub" "PAT" "ghp_token123"
  seed_op_legacy "ikma" "GitHub" "password" "gh-pass"
  seed_op_legacy "ikma" "GPG" "Private Key" "privkey"
  seed_op_legacy "ikma" "GPG" "Public Key" "pubkey"
  seed_op_legacy "ikma" "GPG" "Key ID" "ABCD1234"
  seed_op_legacy "ikma" "GPG" "Fingerprint" "ABCD1234ABCD1234"
  seed_op_legacy "ikma" "Email" "password" "email-pass"
  seed_op_legacy "ikma" "Matrix" "password" "matrix-pass"
  seed_op_legacy "ikma" "Identity" "passphrase" "my-phrase"

  run_migrate "ikma"
  [ "$status" -eq 0 ]
  [[ "$output" == *"9 migrated"* ]]

  local vault="Agents"
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/github-pat/value")" = "ghp_token123" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/github-password/value")" = "gh-pass" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/gpg-private-key/value")" = "privkey" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/gpg-public-key/value")" = "pubkey" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/gpg-key-id/value")" = "ABCD1234" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/gpg-fingerprint/value")" = "ABCD1234ABCD1234" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/email-password/value")" = "email-pass" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/matrix-password/value")" = "matrix-pass" ]
  [ "$(cat "$MOCK_OP_STORE/$vault/ikma/passphrase/value")" = "my-phrase" ]
}

# --- Dry run ---

@test "migrate --dry-run shows what would be migrated without changes" {
  seed_op_legacy "ikma" "Identity" "passphrase" "SECRET_PASS"
  seed_op_legacy "ikma" "Email" "password" "email-pass"

  run_migrate "ikma" "true"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"2 migrated"* ]]

  # Verify NO flat items were created
  local vault="Agents"
  [ ! -f "$MOCK_OP_STORE/$vault/ikma/passphrase/value" ]
  [ ! -f "$MOCK_OP_STORE/$vault/ikma/email-password/value" ]
}

# --- Skip existing ---

@test "migrate skips keys that already exist in flat format" {
  seed_op_legacy "ikma" "Identity" "passphrase" "old-pass"
  seed_op "ikma/passphrase" "already-migrated"

  run_migrate "ikma"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP passphrase"* ]]

  # Value unchanged
  [ "$(cat "$MOCK_OP_STORE/Agents/ikma/passphrase/value")" = "already-migrated" ]
}

# --- Partial agent ---

@test "migrate handles agent with only some legacy items" {
  seed_op_legacy "ikma" "Email" "password" "email-pass"
  # No other legacy items exist

  run_migrate "ikma"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 migrated"* ]]

  [ -f "$MOCK_OP_STORE/Agents/ikma/email-password/value" ]
}

# --- Missing agent ---

@test "migrate with no legacy items reports zero migrated" {
  run_migrate "nobody"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 migrated"* ]]
}

# --- Agent isolation ---

@test "migrate only touches the specified agent's items" {
  seed_op_legacy "ikma" "Email" "password" "ikma-email"
  seed_op_legacy "zeke" "Email" "password" "zeke-email"

  run_migrate "ikma"
  [ "$status" -eq 0 ]

  # ikma migrated
  [ -f "$MOCK_OP_STORE/Agents/ikma/email-password/value" ]
  # zeke untouched
  [ ! -f "$MOCK_OP_STORE/Agents/zeke/email-password/value" ]
}
