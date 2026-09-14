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

@test "export bundle contains full key names" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent/github-pat" "my-token"
  seed_keychain "test-agent/email-password" "my-pass"

  json=$(secrets export --prefix test-agent)

  [ "$(echo "$json" | jq -r '.["test-agent/github-pat"]')" = "my-token" ]
  [ "$(echo "$json" | jq -r '.["test-agent/email-password"]')" = "my-pass" ]
}

@test "export without --prefix exports all keys" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "agent-a/token" "val-a"
  seed_keychain "agent-b/token" "val-b"

  json=$(secrets export)

  [ "$(echo "$json" | jq -r '.["agent-a/token"]')" = "val-a" ]
  [ "$(echo "$json" | jq -r '.["agent-b/token"]')" = "val-b" ]
}

# --- import ---

@test "import stores secrets into keychain from JSON" {
  export SECRETS_PROVIDER="keychain"

  json='{"test-agent/github-pat":"imported-token","test-agent/email-password":"imported-pass"}'

  run bash -c "printf '%s' '$json' | secrets import"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 2 secret(s)"* ]]

  # Verify the secrets were stored
  source "$LIB_DIR/providers/keychain.sh"
  run keychain_get "test-agent/github-pat"
  [ "$output" = "imported-token" ]

  run keychain_get "test-agent/email-password"
  [ "$output" = "imported-pass" ]
}

@test "import stores secrets into 1password from JSON" {
  export SECRETS_PROVIDER="1password"

  json='{"test-agent/github-pat":"op-imported"}'

  run bash -c "printf '%s' '$json' | secrets import"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/providers/onepassword/provider.sh"
  run op_get "test-agent/github-pat"
  [ "$output" = "op-imported" ]
}

@test "import fails without provider" {
  unset SECRETS_PROVIDER

  run bash -c "echo '{}' | secrets import"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "import fails on invalid JSON" {
  export SECRETS_PROVIDER="keychain"

  run bash -c "echo 'not-json-data' | secrets import"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid JSON"* ]]
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
  result=$(printf '%s' "$json" | secrets import)
  [[ "$result" == *"Imported 2 secret(s)"* ]]

  # Verify in 1password
  source "$LIB_DIR/providers/onepassword/provider.sh"
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
  result=$(printf '%s' "$json" | secrets import)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # Verify in keychain
  source "$LIB_DIR/providers/keychain.sh"
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

  # Delete the original, then re-import to prove import creates (not just overwrites)
  source "$LIB_DIR/providers/keychain.sh"
  keychain_delete "test-agent/gpg-public-key"
  run keychain_get "test-agent/gpg-public-key"
  [ "$status" -ne 0 ]

  # Import
  result=$(printf '%s' "$json" | secrets import)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  # Verify: the imported value must NOT have wrapping quotes
  run keychain_get "test-agent/gpg-public-key"
  [ "$status" -eq 0 ]
  [[ "$output" == "-----BEGIN PGP PUBLIC KEY BLOCK-----"* ]]
  [[ "$output" == *"-----END PGP PUBLIC KEY BLOCK-----" ]]
  [[ "$output" != '"'* ]]
}

@test "export preserves literal wrapping quotes" {
  # Quotes can be intentional secret bytes, not a repairable encoding mistake.
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
  result=$(printf '%s' "$json" | secrets import)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/providers/keychain.sh"
  run keychain_get "test-agent/gpg-public-key"
  [ "$status" -eq 0 ]
  [ "$output" = "$quoted_key" ]
}

@test "roundtrip preserves arbitrary key names" {
  seed_keychain "test-agent/my-custom-key" "custom-val"

  export SECRETS_PROVIDER="keychain"
  json=$(secrets export --prefix test-agent)

  export SECRETS_PROVIDER="1password"
  result=$(printf '%s' "$json" | secrets import)
  [[ "$result" == *"Imported 1 secret(s)"* ]]

  source "$LIB_DIR/providers/onepassword/provider.sh"
  run op_get "test-agent/my-custom-key"
  [ "$output" = "custom-val" ]
}
