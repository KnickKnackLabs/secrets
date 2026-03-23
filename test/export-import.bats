#!/usr/bin/env bats
# Tests for export/import tasks.
# Export produces plain JSON, import reads plain JSON.

load helpers

setup() {
  setup_test_env
  create_mock_security
  create_mock_op

  export MISE_PROJECT_ROOT="$REPO_DIR"
}

# --- export ---

@test "export produces JSON output from keychain" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent/github-pat" "my-token"
  seed_keychain "test-agent/email-password" "my-pass"

  run secrets export --prefix test-agent
  [ "$status" -eq 0 ]
  # Output should be valid JSON
  echo "$output" | jq . >/dev/null 2>&1
}

@test "export produces JSON output from 1password" {
  export SECRETS_PROVIDER="1password"
  seed_op "test-agent/github-pat" "op-token"

  run secrets export --prefix test-agent
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "export fails with no secrets" {
  export SECRETS_PROVIDER="keychain"

  run secrets export --prefix test-agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secrets found"* ]]
}

@test "export fails without provider" {
  unset SECRETS_PROVIDER

  run secrets export --prefix test-agent
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "export bundle contains correct JSON" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent/github-pat" "my-token"
  seed_keychain "test-agent/email-password" "my-pass"

  json=$(secrets export --prefix test-agent)

  [ "$(echo "$json" | jq -r '.["github-pat"]')" = "my-token" ]
  [ "$(echo "$json" | jq -r '.["email-password"]')" = "my-pass" ]
}

# --- import ---

@test "import stores secrets into keychain from JSON" {
  export SECRETS_PROVIDER="keychain"

  json='{"github-pat":"imported-token","email-password":"imported-pass"}'

  run bash -c "printf '%s' '$json' | secrets import --prefix test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 2 secret(s)"* ]]

  # Verify the secrets were stored
  source "$LIB_DIR/keychain.sh"
  run keychain_get "test-agent/github-pat"
  [ "$output" = "imported-token" ]

  run keychain_get "test-agent/email-password"
  [ "$output" = "imported-pass" ]
}

@test "import stores secrets into 1password from JSON" {
  export SECRETS_PROVIDER="1password"

  json='{"github-pat":"op-imported"}'

  run bash -c "printf '%s' '$json' | secrets import --prefix test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/1password.sh"
  run op_get "test-agent/github-pat"
  [ "$output" = "op-imported" ]
}

@test "import fails without provider" {
  unset SECRETS_PROVIDER

  run bash -c "echo '{}' | secrets import --prefix test-agent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "import fails on invalid JSON" {
  export SECRETS_PROVIDER="keychain"

  run bash -c "echo 'not-json-data' | secrets import --prefix test-agent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
}

# --- export/import roundtrip ---

@test "roundtrip: export from keychain, import to 1password" {
  # Seed keychain
  seed_keychain "test-agent/github-pat" "roundtrip-token"
  seed_keychain "test-agent/email-password" "roundtrip-pass"

  # Export from keychain
  export SECRETS_PROVIDER="keychain"
  json=$(secrets export --prefix test-agent)

  # Import to 1password
  export SECRETS_PROVIDER="1password"
  result=$(printf '%s' "$json" | secrets import --prefix test-agent)
  [[ "$result" == *"Imported 2 secret(s)"* ]]

  # Verify in 1password
  source "$LIB_DIR/1password.sh"
  run op_get "test-agent/github-pat"
  [ "$output" = "roundtrip-token" ]

  run op_get "test-agent/email-password"
  [ "$output" = "roundtrip-pass" ]
}

@test "roundtrip: export from 1password, import to keychain" {
  # Seed 1password
  seed_op "test-agent/github-pat" "op-roundtrip"

  # Export from 1password
  export SECRETS_PROVIDER="1password"
  json=$(secrets export --prefix test-agent)

  # Import to keychain
  export SECRETS_PROVIDER="keychain"
  result=$(printf '%s' "$json" | secrets import --prefix test-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # Verify in keychain
  source "$LIB_DIR/keychain.sh"
  run keychain_get "test-agent/github-pat"
  [ "$output" = "op-roundtrip" ]
}

@test "roundtrip preserves multiline values (PGP keys)" {
  local pgp_key="-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGm7e/kBEADHt2uVu3BCD9DnZcXycdeTHsgRbclF6g+o7VRT4Or9DZ451eIP
vl9kC7fIz3GLf05wAlPGskvoBP894c0fRjJCeyTfTzRu9dZWuJUqODElWHnpmXD6
-----END PGP PUBLIC KEY BLOCK-----"

  seed_keychain "test-agent/gpg-public-key" "$pgp_key"

  # Export from keychain
  export SECRETS_PROVIDER="keychain"
  json=$(secrets export --prefix test-agent)

  # Import to a fresh prefix
  result=$(printf '%s' "$json" | secrets import --prefix other-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # Verify: the imported value must NOT have wrapping quotes
  source "$LIB_DIR/keychain.sh"
  run keychain_get "other-agent/gpg-public-key"
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
  seed_keychain "test-agent/gpg-public-key" "$quoted_key"

  # Export
  export SECRETS_PROVIDER="keychain"
  json=$(secrets export --prefix test-agent)

  # Import
  result=$(printf '%s' "$json" | secrets import --prefix other-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # The imported value must NOT have wrapping quotes
  source "$LIB_DIR/keychain.sh"
  run keychain_get "other-agent/gpg-public-key"
  [ "$status" -eq 0 ]
  [[ "$output" == "-----BEGIN PGP PUBLIC KEY BLOCK-----"* ]]
  [[ "$output" != '"'* ]]
}

@test "roundtrip preserves arbitrary key names" {
  seed_keychain "test-agent/my-custom-key" "custom-val"

  export SECRETS_PROVIDER="keychain"
  json=$(secrets export --prefix test-agent)

  export SECRETS_PROVIDER="1password"
  result=$(printf '%s' "$json" | secrets import --prefix test-agent)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/1password.sh"
  run op_get "test-agent/my-custom-key"
  [ "$output" = "custom-val" ]
}
