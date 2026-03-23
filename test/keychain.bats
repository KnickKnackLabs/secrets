#!/usr/bin/env bats
# Tests for the keychain provider (lib/keychain.sh).
# Uses a mock security binary — no real keychain interaction.

load helpers

setup() {
  setup_test_env
  create_mock_security
  source "$LIB_DIR/keychain.sh"
}

# --- keychain_set ---

@test "keychain_set stores a value" {
  run keychain_set "test-agent/github-pat" "my-secret-token"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stored:"* ]]
  [[ "$output" == *"key=test-agent/github-pat"* ]]
}

@test "keychain_set stores base64-encoded value in keychain" {
  keychain_set "test-agent/github-pat" "my-secret-token"

  # Check the mock keychain file has base64 content
  local service="${SECRETS_SERVICE_PREFIX}test-agent/github-pat"
  local stored
  stored=$(cat "$MOCK_KEYCHAIN/$SECRETS_KEYCHAIN_ACCOUNT/$service")
  local decoded
  decoded=$(printf '%s' "$stored" | base64 --decode)
  [ "$decoded" = "my-secret-token" ]
}

@test "keychain_set reads from stdin when no value argument" {
  echo -n "stdin-value" | keychain_set "test-agent/email-password"

  # Verify it was stored
  run keychain_get "test-agent/email-password"
  [ "$status" -eq 0 ]
  [ "$output" = "stdin-value" ]
}

@test "keychain_set fails on empty value" {
  run keychain_set "test-agent/github-pat" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "keychain_set updates existing value" {
  keychain_set "test-agent/github-pat" "old-value"
  keychain_set "test-agent/github-pat" "new-value"

  run keychain_get "test-agent/github-pat"
  [ "$output" = "new-value" ]
}

# --- keychain_get ---

@test "keychain_get retrieves a stored value" {
  seed_keychain "test-agent/github-pat" "my-token"

  run keychain_get "test-agent/github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "my-token" ]
}

@test "keychain_get fails for nonexistent key" {
  run keychain_get "test-agent/nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"No keychain entry found"* ]]
}

@test "keychain_get handles multi-line values" {
  local multiline="line1
line2
line3"
  seed_keychain "test-agent/gpg-private-key" "$multiline"

  run keychain_get "test-agent/gpg-private-key"
  [ "$status" -eq 0 ]
  [ "$output" = "$multiline" ]
}

@test "keychain_get isolates prefixes — different prefixes have different values" {
  seed_keychain "alice/github-pat" "alice-token"
  seed_keychain "bob/github-pat" "bob-token"

  run keychain_get "alice/github-pat"
  [ "$output" = "alice-token" ]

  run keychain_get "bob/github-pat"
  [ "$output" = "bob-token" ]
}

# --- keychain_set + keychain_get roundtrip ---

@test "roundtrip: set then get returns original value" {
  keychain_set "test-agent/matrix-password" "s3cr3t!"

  run keychain_get "test-agent/matrix-password"
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t!" ]
}

@test "roundtrip: handles special characters" {
  local special='p@$$w0rd!#%&*(){}[]|/<>'
  keychain_set "test-agent/email-password" "$special"

  run keychain_get "test-agent/email-password"
  [ "$status" -eq 0 ]
  [ "$output" = "$special" ]
}

# --- SECRETS_SERVICE_PREFIX ---

@test "uses SECRETS_SERVICE_PREFIX in service name" {
  export SECRETS_SERVICE_PREFIX="custom-prefix/"
  # Re-source to pick up new prefix
  source "$LIB_DIR/keychain.sh"

  keychain_set "test-agent/github-pat" "my-token"

  # Check the file is stored under the custom prefix
  [ -f "$MOCK_KEYCHAIN/$SECRETS_KEYCHAIN_ACCOUNT/custom-prefix/test-agent/github-pat" ]
}

# --- keychain_list (dynamic discovery) ---

@test "keychain_list discovers stored keys for a prefix" {
  seed_keychain "test-agent/github-pat" "token1"
  seed_keychain "test-agent/email-password" "pass1"

  run keychain_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/email-password"* ]]
  [[ "$output" == *"✓ test-agent/github-pat"* ]]
}

@test "keychain_list shows nothing for prefix with no secrets" {
  run keychain_list "nobody"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no secrets found"* ]]
}

@test "keychain_list without prefix shows all entries" {
  seed_keychain "alice/github-pat" "a-token"
  seed_keychain "bob/email-password" "b-pass"

  run keychain_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice/github-pat"* ]]
  [[ "$output" == *"bob/email-password"* ]]
}

# --- field ordering robustness ---

@test "keychain_list finds all keys regardless of dump-keychain field ordering" {
  # The mock alternates acct/svce ordering per entry. Seed enough entries
  # that some will have acct-before-svce and some svce-before-acct.
  seed_keychain "test-agent/key-a" "val-a"
  seed_keychain "test-agent/key-b" "val-b"
  seed_keychain "test-agent/key-c" "val-c"
  seed_keychain "other-agent/key-d" "val-d"

  run keychain_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/key-a"* ]]
  [[ "$output" == *"✓ test-agent/key-b"* ]]
  [[ "$output" == *"✓ test-agent/key-c"* ]]
  # Must not include other-agent's keys
  [[ "$output" != *"other-agent/key-d"* ]]
}

# --- any key name works ---

@test "keychain accepts arbitrary key names" {
  keychain_set "test-agent/my-custom-key" "custom-value"

  run keychain_get "test-agent/my-custom-key"
  [ "$status" -eq 0 ]
  [ "$output" = "custom-value" ]
}

@test "keychain_list discovers arbitrary key names" {
  seed_keychain "test-agent/my-custom-key" "val1"
  seed_keychain "test-agent/another-thing" "val2"

  run keychain_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/another-thing"* ]]
  [[ "$output" == *"✓ test-agent/my-custom-key"* ]]
}
