#!/usr/bin/env bats
# Tests for export/import tasks.
# Uses mock GPG (base64), mock keychain, and mock 1Password.

load helpers

setup() {
  setup_test_env
  create_mock_security
  create_mock_op
  create_mock_gpg

  export MISE_PROJECT_ROOT="$REPO_DIR"
}

# --- export ---

@test "export produces GPG-encrypted output from keychain" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent" "github-pat" "my-token"
  seed_keychain "test-agent" "email-password" "my-pass"

  run mise -C "$REPO_DIR" run -q export test-agent
  [ "$status" -eq 0 ]
  # Output should be "encrypted" (mock GPG marker)
  [[ "$output" == "MOCK-GPG-ENCRYPTED:"* ]]
}

@test "export produces GPG-encrypted output from 1password" {
  export SECRETS_PROVIDER="1password"
  seed_op "test-agent" "github-pat" "op-token"

  run mise -C "$REPO_DIR" run -q export test-agent
  [ "$status" -eq 0 ]
  [[ "$output" == "MOCK-GPG-ENCRYPTED:"* ]]
}

@test "export fails with no secrets" {
  export SECRETS_PROVIDER="keychain"

  run mise -C "$REPO_DIR" run -q export test-agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secrets found"* ]]
}

@test "export fails without provider" {
  unset SECRETS_PROVIDER

  run mise -C "$REPO_DIR" run -q export test-agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "export bundle contains correct JSON when decrypted" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent" "github-pat" "my-token"
  seed_keychain "test-agent" "email-password" "my-pass"

  # Export and decrypt (mock GPG just base64-encodes)
  encrypted=$(mise -C "$REPO_DIR" run -q export test-agent)
  # Strip mock GPG marker and decode
  encoded="${encrypted#MOCK-GPG-ENCRYPTED:}"
  json=$(printf '%s' "$encoded" | base64 --decode)

  # Verify JSON structure
  run printf '%s' "$json"
  [ "$(echo "$json" | jq -r '.["github-pat"]')" = "my-token" ]
  [ "$(echo "$json" | jq -r '.["email-password"]')" = "my-pass" ]
}

@test "export uses --encrypt-to flag" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent" "github-pat" "my-token"

  # Should succeed with custom recipient (mock GPG ignores it)
  run mise -C "$REPO_DIR" run -q export test-agent --encrypt-to custom@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == "MOCK-GPG-ENCRYPTED:"* ]]
}

# --- import ---

@test "import stores secrets into keychain from encrypted bundle" {
  export SECRETS_PROVIDER="keychain"

  # Build a mock-encrypted bundle
  json='{"github-pat":"imported-token","email-password":"imported-pass"}'
  encrypted=$(printf '%s' "$json" | "$GPG" --encrypt --armor --recipient test@test.com --trust-model always)

  # Import it
  run bash -c "printf '%s' '$encrypted' | mise -C '$REPO_DIR' run -q import test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 2 secret(s)"* ]]

  # Verify the secrets were stored
  source "$LIB_DIR/keychain.sh"
  run keychain_get "test-agent" "github-pat"
  [ "$output" = "imported-token" ]

  run keychain_get "test-agent" "email-password"
  [ "$output" = "imported-pass" ]
}

@test "import stores secrets into 1password from encrypted bundle" {
  export SECRETS_PROVIDER="1password"

  json='{"github-pat":"op-imported"}'
  encrypted=$(printf '%s' "$json" | "$GPG" --encrypt --armor --recipient test@test.com --trust-model always)

  run bash -c "printf '%s' '$encrypted' | mise -C '$REPO_DIR' run -q import test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/1password.sh"
  run op_get "test-agent" "github-pat"
  [ "$output" = "op-imported" ]
}

@test "import fails without provider" {
  unset SECRETS_PROVIDER

  run bash -c "echo 'data' | mise -C '$REPO_DIR' run -q import test-agent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "import fails on invalid encrypted data" {
  export SECRETS_PROVIDER="keychain"

  run bash -c "echo 'not-encrypted-data' | mise -C '$REPO_DIR' run -q import test-agent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GPG decryption failed"* ]]
}

# --- export/import roundtrip ---

@test "roundtrip: export from keychain, import to 1password" {
  # Seed keychain
  seed_keychain "test-agent" "github-pat" "roundtrip-token"
  seed_keychain "test-agent" "email-password" "roundtrip-pass"

  # Export from keychain
  export SECRETS_PROVIDER="keychain"
  encrypted=$(mise -C "$REPO_DIR" run -q export test-agent)

  # Import to 1password
  export SECRETS_PROVIDER="1password"
  result=$(printf '%s' "$encrypted" | mise -C "$REPO_DIR" run -q import test-agent)
  [[ "$result" == *"Imported 2 secret(s)"* ]]

  # Verify in 1password
  source "$LIB_DIR/1password.sh"
  run op_get "test-agent" "github-pat"
  [ "$output" = "roundtrip-token" ]

  run op_get "test-agent" "email-password"
  [ "$output" = "roundtrip-pass" ]
}

@test "roundtrip: export from 1password, import to keychain" {
  # Seed 1password
  seed_op "test-agent" "github-pat" "op-roundtrip"

  # Export from 1password
  export SECRETS_PROVIDER="1password"
  encrypted=$(mise -C "$REPO_DIR" run -q export test-agent)

  # Import to keychain
  export SECRETS_PROVIDER="keychain"
  result=$(printf '%s' "$encrypted" | mise -C "$REPO_DIR" run -q import test-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # Verify in keychain
  source "$LIB_DIR/keychain.sh"
  run keychain_get "test-agent" "github-pat"
  [ "$output" = "op-roundtrip" ]
}

@test "roundtrip preserves multiline values (PGP keys)" {
  local pgp_key="-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGm7e/kBEADHt2uVu3BCD9DnZcXycdeTHsgRbclF6g+o7VRT4Or9DZ451eIP
vl9kC7fIz3GLf05wAlPGskvoBP894c0fRjJCeyTfTzRu9dZWuJUqODElWHnpmXD6
-----END PGP PUBLIC KEY BLOCK-----"

  seed_keychain "test-agent" "gpg-public-key" "$pgp_key"

  # Export from keychain
  export SECRETS_PROVIDER="keychain"
  encrypted=$(mise -C "$REPO_DIR" run -q export test-agent)

  # Import to a fresh keychain-backed agent
  result=$(printf '%s' "$encrypted" | mise -C "$REPO_DIR" run -q import other-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # Verify: the imported value must NOT have wrapping quotes
  source "$LIB_DIR/keychain.sh"
  run keychain_get "other-agent" "gpg-public-key"
  [ "$status" -eq 0 ]
  [[ "$output" == "-----BEGIN PGP PUBLIC KEY BLOCK-----"* ]]
  [[ "$output" == *"-----END PGP PUBLIC KEY BLOCK-----" ]]
  # Must not start with a literal double-quote
  [[ "$output" != '"'* ]]
}

@test "export strips wrapping quotes from double-encoded values" {
  # Regression: some providers (old shimmer, 1Password manual entry) store
  # values with literal wrapping double-quotes, e.g. '"-----BEGIN PGP..."'.
  # Export should strip these before JSON-encoding so the roundtrip is clean.
  local raw_key="-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGm7e/kBEADHt2uVu3BCD9DnZcXycdeTHsgRbclF6g+o7VRT4Or9DZ451eIP
-----END PGP PUBLIC KEY BLOCK-----"

  # Store with wrapping quotes (simulating double-encoded 1Password value)
  local quoted_key="\"${raw_key}\""
  seed_keychain "test-agent" "gpg-public-key" "$quoted_key"

  # Export
  export SECRETS_PROVIDER="keychain"
  encrypted=$(mise -C "$REPO_DIR" run -q export test-agent)

  # Import
  result=$(printf '%s' "$encrypted" | mise -C "$REPO_DIR" run -q import other-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # The imported value must NOT have wrapping quotes
  source "$LIB_DIR/keychain.sh"
  run keychain_get "other-agent" "gpg-public-key"
  [ "$status" -eq 0 ]
  [[ "$output" == "-----BEGIN PGP PUBLIC KEY BLOCK-----"* ]]
  [[ "$output" != '"'* ]]
}

@test "roundtrip preserves arbitrary key names" {
  seed_keychain "test-agent" "my-custom-key" "custom-val"

  export SECRETS_PROVIDER="keychain"
  encrypted=$(mise -C "$REPO_DIR" run -q export test-agent)

  export SECRETS_PROVIDER="1password"
  result=$(printf '%s' "$encrypted" | mise -C "$REPO_DIR" run -q import test-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/1password.sh"
  run op_get "test-agent" "my-custom-key"
  [ "$output" = "custom-val" ]
}
