#!/usr/bin/env bats
# Tests for the libsecret provider (lib/libsecret.sh).
# Uses a mock secret-tool binary — no real keyring interaction.

load helpers

setup() {
  setup_test_env
  create_mock_secret_tool
  source "$LIB_DIR/libsecret.sh"
}

# --- libsecret_set ---

@test "libsecret_set stores a value" {
  run libsecret_set "test-agent/github-pat" "my-secret-token"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stored:"* ]]
  [[ "$output" == *"key=test-agent/github-pat"* ]]
}

@test "libsecret_set stores base64-encoded value in keyring" {
  libsecret_set "test-agent/github-pat" "my-secret-token"

  local service="${SECRETS_SERVICE_PREFIX}test-agent/github-pat"
  local stored
  stored=$(cat "$MOCK_LIBSECRET/$SECRETS_LIBSECRET_ACCOUNT/$service")
  local decoded
  decoded=$(printf '%s' "$stored" | base64 --decode)
  [ "$decoded" = "my-secret-token" ]
}

@test "a value stored by libsecret reads back through keychain" {
  create_mock_security
  source "$LIB_DIR/keychain.sh"
  local value="~~?
?>~"

  libsecret_set "test-agent/gpg-private-key" "$value"

  local service="${SECRETS_SERVICE_PREFIX}test-agent/gpg-private-key"
  local dst="$MOCK_KEYCHAIN/$SECRETS_KEYCHAIN_ACCOUNT/$service"
  mkdir -p "$(dirname "$dst")"
  cp "$MOCK_LIBSECRET/$SECRETS_LIBSECRET_ACCOUNT/$service" "$dst"

  run keychain_get "test-agent/gpg-private-key"
  [ "$status" -eq 0 ]
  [ "$output" = "$value" ]
}

@test "libsecret_set reads from stdin when no value argument" {
  echo -n "stdin-value" | libsecret_set "test-agent/email-password"

  run libsecret_get "test-agent/email-password"
  [ "$status" -eq 0 ]
  [ "$output" = "stdin-value" ]
}

@test "libsecret_set fails on empty value" {
  run libsecret_set "test-agent/github-pat" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "libsecret_set updates existing value" {
  libsecret_set "test-agent/github-pat" "old-value"
  libsecret_set "test-agent/github-pat" "new-value"

  run libsecret_get "test-agent/github-pat"
  [ "$output" = "new-value" ]
}

# --- libsecret_get ---

@test "libsecret_get retrieves a stored value" {
  seed_libsecret "test-agent/github-pat" "my-token"

  run libsecret_get "test-agent/github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "my-token" ]
}

@test "libsecret_get fails for nonexistent key" {
  run libsecret_get "test-agent/nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"No keyring entry found"* ]]
}

@test "libsecret_get reports a dead secret service, not a missing key" {
  seed_libsecret "test-agent/github-pat" "my-token"
  export MOCK_SECRET_TOOL_DBUS_ERROR=1

  run libsecret_get "test-agent/github-pat"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No running secret service"* ]]
  [[ "$output" != *"No keyring entry found"* ]]
}

@test "libsecret_get passes the secret-tool diagnostic through" {
  export MOCK_SECRET_TOOL_DBUS_ERROR=1

  run libsecret_get "test-agent/github-pat"
  [[ "$output" == *"Cannot autolaunch D-Bus"* ]]
}

@test "libsecret_get handles multi-line values" {
  local multiline="line1
line2
line3"
  seed_libsecret "test-agent/gpg-private-key" "$multiline"

  run libsecret_get "test-agent/gpg-private-key"
  [ "$status" -eq 0 ]
  [ "$output" = "$multiline" ]
}

@test "libsecret_get isolates prefixes — different prefixes have different values" {
  seed_libsecret "alice/github-pat" "alice-token"
  seed_libsecret "bob/github-pat" "bob-token"

  run libsecret_get "alice/github-pat"
  [ "$output" = "alice-token" ]

  run libsecret_get "bob/github-pat"
  [ "$output" = "bob-token" ]
}

# --- libsecret_set + libsecret_get roundtrip ---

@test "roundtrip: set then get returns original value" {
  libsecret_set "test-agent/matrix-password" "s3cr3t!"

  run libsecret_get "test-agent/matrix-password"
  [ "$status" -eq 0 ]
  [ "$output" = "s3cr3t!" ]
}

@test "roundtrip: handles special characters" {
  local special='p@$$w0rd!#%&*(){}[]|/<>'
  libsecret_set "test-agent/email-password" "$special"

  run libsecret_get "test-agent/email-password"
  [ "$status" -eq 0 ]
  [ "$output" = "$special" ]
}

# --- SECRETS_SERVICE_PREFIX ---

@test "uses SECRETS_SERVICE_PREFIX in service name" {
  export SECRETS_SERVICE_PREFIX="custom-prefix/"
  # Re-source to pick up new prefix
  source "$LIB_DIR/libsecret.sh"

  libsecret_set "test-agent/github-pat" "my-token"

  [ -f "$MOCK_LIBSECRET/$SECRETS_LIBSECRET_ACCOUNT/custom-prefix/test-agent/github-pat" ]
}

# --- libsecret_delete ---

@test "libsecret_delete removes a stored key" {
  seed_libsecret "test-agent/github-pat" "my-token"

  run libsecret_delete "test-agent/github-pat"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted:"* ]]

  run libsecret_get "test-agent/github-pat"
  [ "$status" -ne 0 ]
}

@test "libsecret_delete fails for nonexistent key" {
  # secret-tool clear exits 0 whether or not anything matched, so the provider
  # has to check existence itself — otherwise deleting nothing looks like success.
  run libsecret_delete "test-agent/nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No keyring entry found"* ]]
}

# --- libsecret_rename ---

@test "libsecret_rename moves a value to the new key" {
  seed_libsecret "test-agent/old-name" "carried-over"

  run libsecret_rename "test-agent/old-name" "test-agent/new-name"
  [ "$status" -eq 0 ]

  run libsecret_get "test-agent/new-name"
  [ "$output" = "carried-over" ]

  run libsecret_get "test-agent/old-name"
  [ "$status" -ne 0 ]
}

@test "libsecret_rename rejects identical names" {
  run libsecret_rename "test-agent/same" "test-agent/same"
  [ "$status" -ne 0 ]
  [[ "$output" == *"same"* ]]
}

# --- libsecret_list (dynamic discovery) ---

@test "libsecret_list discovers stored keys for a prefix" {
  seed_libsecret "test-agent/github-pat" "token1"
  seed_libsecret "test-agent/email-password" "pass1"

  run libsecret_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/email-password"* ]]
  [[ "$output" == *"✓ test-agent/github-pat"* ]]
}

@test "libsecret_list shows nothing for prefix with no secrets" {
  run libsecret_list "nobody"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no secrets found"* ]]
}

@test "libsecret_list without prefix shows all entries" {
  seed_libsecret "alice/github-pat" "a-token"
  seed_libsecret "bob/email-password" "b-pass"

  run libsecret_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice/github-pat"* ]]
  [[ "$output" == *"bob/email-password"* ]]
}

@test "libsecret_list filters out non-matching prefixes" {
  seed_libsecret "test-agent/key-a" "val-a"
  seed_libsecret "other-agent/key-d" "val-d"

  run libsecret_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/key-a"* ]]
  [[ "$output" != *"other-agent/key-d"* ]]
}

# --- secret-tool's split output ---

@test "libsecret_list reads attributes that secret-tool writes to stderr" {
  # Regression guard: secret-tool prints "attribute.*" lines on stderr and the
  # rest on stdout. Discarding stderr makes discovery silently return nothing.
  seed_libsecret "test-agent/github-pat" "token1"

  run libsecret_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/github-pat"* ]]
}

@test "libsecret_list reports a dead secret service, not an empty keyring" {
  seed_libsecret "test-agent/github-pat" "my-token"
  export MOCK_SECRET_TOOL_DBUS_ERROR=1

  run libsecret_list "test-agent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No running secret service"* ]]
  [[ "$output" != *"no secrets found"* ]]
}

@test "libsecret_list reports an empty keyring as empty, not as a dead service" {
  run libsecret_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no secrets found"* ]]
}

@test "libsecret_list never prints secret values" {
  # Unlike macOS dump-keychain, secret-tool search prints the secret itself.
  seed_libsecret "test-agent/github-pat" "super-secret-value"

  run libsecret_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" != *"super-secret-value"* ]]
  # ...and not the stored base64 form either
  [[ "$output" != *"c3VwZXItc2VjcmV0LXZhbHVl"* ]]
}

# --- any key name works ---

@test "libsecret accepts arbitrary key names" {
  libsecret_set "test-agent/my-custom-key" "custom-value"

  run libsecret_get "test-agent/my-custom-key"
  [ "$status" -eq 0 ]
  [ "$output" = "custom-value" ]
}

@test "libsecret_list discovers arbitrary key names" {
  seed_libsecret "test-agent/my-custom-key" "val1"
  seed_libsecret "test-agent/another-thing" "val2"

  run libsecret_list "test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ test-agent/another-thing"* ]]
  [[ "$output" == *"✓ test-agent/my-custom-key"* ]]
}
