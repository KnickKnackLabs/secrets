#!/usr/bin/env bats
# Integration tests: full CRUD lifecycle through mise tasks.
#
# Exercises the complete user-facing workflow:
#   set → get → list → set (update) → rename → remove
#
# Tests both providers (keychain, 1password) and cross-cutting concerns
# (prefix isolation, export/import roundtrip).

load helpers

setup() {
  setup_test_env
  create_mock_security
  create_mock_op
  export MISE_PROJECT_ROOT="$REPO_DIR"
}

# ============================================================
# Keychain: full CRUD lifecycle
# ============================================================

@test "keychain crud: set → get → list → update → rename → remove" {
  export SECRETS_PROVIDER="keychain"

  # -- Create --
  run secrets set test-agent/api-key --value "original-value"
  [ "$status" -eq 0 ]

  # -- Read --
  run secrets get test-agent/api-key
  [ "$status" -eq 0 ]
  [ "$output" = "original-value" ]

  # -- List shows it --
  run secrets list test-agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"api-key"* ]]

  # -- Update (overwrite) --
  run secrets set test-agent/api-key --value "updated-value"
  [ "$status" -eq 0 ]

  run secrets get test-agent/api-key
  [ "$status" -eq 0 ]
  [ "$output" = "updated-value" ]

  # -- Rename --
  run secrets rename test-agent/api-key test-agent/new-api-key
  [ "$status" -eq 0 ]

  # New key has the value
  run secrets get test-agent/new-api-key
  [ "$status" -eq 0 ]
  [ "$output" = "updated-value" ]

  # Old key is gone
  run secrets get test-agent/api-key
  [ "$status" -ne 0 ]

  # -- Remove --
  run secrets remove test-agent/new-api-key
  [ "$status" -eq 0 ]

  # Verify it's gone
  run secrets get test-agent/new-api-key
  [ "$status" -ne 0 ]

  # List shows nothing
  run secrets list test-agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"no secrets found"* ]]
}

# ============================================================
# 1Password: full CRUD lifecycle
# ============================================================

@test "1password crud: set → get → list → update → rename → remove" {
  export SECRETS_PROVIDER="1password"

  # -- Create --
  run secrets set test-agent/api-key --value "original-value"
  [ "$status" -eq 0 ]

  # -- Read --
  run secrets get test-agent/api-key
  [ "$status" -eq 0 ]
  [ "$output" = "original-value" ]

  # -- List shows it --
  run secrets list test-agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"api-key"* ]]

  # -- Update (overwrite) --
  run secrets set test-agent/api-key --value "updated-value"
  [ "$status" -eq 0 ]

  run secrets get test-agent/api-key
  [ "$status" -eq 0 ]
  [ "$output" = "updated-value" ]

  # -- Rename --
  run secrets rename test-agent/api-key test-agent/new-api-key
  [ "$status" -eq 0 ]

  # New key has the value
  run secrets get test-agent/new-api-key
  [ "$status" -eq 0 ]
  [ "$output" = "updated-value" ]

  # Old key is gone
  run secrets get test-agent/api-key
  [ "$status" -ne 0 ]

  # -- Remove --
  run secrets remove test-agent/new-api-key
  [ "$status" -eq 0 ]

  # Verify it's gone
  run secrets get test-agent/new-api-key
  [ "$status" -ne 0 ]
}

# ============================================================
# Prefix isolation (keys with different prefixes don't interfere)
# ============================================================

@test "keychain crud: prefixes are isolated from each other" {
  export SECRETS_PROVIDER="keychain"

  # Store same relative key name under two different prefixes
  secrets set alice/db-password --value "alice-secret"
  secrets set bob/db-password --value "bob-secret"

  # Each prefix sees only their own value
  run secrets get alice/db-password
  [ "$output" = "alice-secret" ]

  run secrets get bob/db-password
  [ "$output" = "bob-secret" ]

  # Removing alice's key doesn't affect bob's
  secrets remove alice/db-password

  run secrets get alice/db-password
  [ "$status" -ne 0 ]

  run secrets get bob/db-password
  [ "$status" -eq 0 ]
  [ "$output" = "bob-secret" ]
}

@test "1password crud: prefixes are isolated from each other" {
  export SECRETS_PROVIDER="1password"

  secrets set alice/db-password --value "alice-secret"
  secrets set bob/db-password --value "bob-secret"

  run secrets get alice/db-password
  [ "$output" = "alice-secret" ]

  run secrets get bob/db-password
  [ "$output" = "bob-secret" ]

  secrets remove alice/db-password

  run secrets get alice/db-password
  [ "$status" -ne 0 ]

  run secrets get bob/db-password
  [ "$status" -eq 0 ]
  [ "$output" = "bob-secret" ]
}

# ============================================================
# Multiple secrets per prefix
# ============================================================

@test "keychain crud: multiple secrets per prefix" {
  export SECRETS_PROVIDER="keychain"

  secrets set test-agent/github-pat --value "gh-token"
  secrets set test-agent/email-password --value "em-pass"
  secrets set test-agent/gpg-passphrase --value "gpg-pp"

  # List shows all three
  run secrets list test-agent
  [ "$status" -eq 0 ]
  [[ "$output" == *"github-pat"* ]]
  [[ "$output" == *"email-password"* ]]
  [[ "$output" == *"gpg-passphrase"* ]]

  # Remove one, others survive
  secrets remove test-agent/email-password

  run secrets get test-agent/github-pat
  [ "$output" = "gh-token" ]
  run secrets get test-agent/gpg-passphrase
  [ "$output" = "gpg-pp" ]
  run secrets get test-agent/email-password
  [ "$status" -ne 0 ]
}

# ============================================================
# Special characters & edge cases
# ============================================================

@test "keychain crud: special characters survive roundtrip" {
  export SECRETS_PROVIDER="keychain"

  local special='p@$$w0rd!#%&*(){}[]|/<>'
  secrets set test-agent/weird-key --value "$special"

  run secrets get test-agent/weird-key
  [ "$status" -eq 0 ]
  [ "$output" = "$special" ]
}

@test "1password crud: special characters survive roundtrip" {
  export SECRETS_PROVIDER="1password"

  local special='p@$$w0rd!#%&*(){}[]|/<>'
  secrets set test-agent/weird-key --value "$special"

  run secrets get test-agent/weird-key
  [ "$status" -eq 0 ]
  [ "$output" = "$special" ]
}

@test "keychain crud: multi-line value survives set/get" {
  export SECRETS_PROVIDER="keychain"

  local multiline="-----BEGIN PGP PRIVATE KEY-----
mDMEZ+abc123...
=ABCD
-----END PGP PRIVATE KEY-----"

  printf '%s' "$multiline" | secrets set test-agent/gpg-key

  run secrets get test-agent/gpg-key
  [ "$status" -eq 0 ]
  [ "$output" = "$multiline" ]
}

# ============================================================
# Export / Import roundtrip
# ============================================================

@test "keychain crud: export then import preserves all secrets" {
  export SECRETS_PROVIDER="keychain"

  # Seed some secrets
  secrets set test-agent/github-pat --value "gh-token-123"
  secrets set test-agent/email-password --value "em-pass-456"

  # Export (produces plain JSON)
  run secrets export --prefix test-agent
  [ "$status" -eq 0 ]
  local exported="$output"

  # Wipe the originals
  secrets remove test-agent/github-pat
  secrets remove test-agent/email-password

  # Verify they're gone
  run secrets get test-agent/github-pat
  [ "$status" -ne 0 ]

  # Import them back
  run bash -c "printf '%s' '$exported' | secrets import --prefix test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 2 secret(s)"* ]]

  # Verify restored
  run secrets get test-agent/github-pat
  [ "$status" -eq 0 ]
  [ "$output" = "gh-token-123" ]

  run secrets get test-agent/email-password
  [ "$status" -eq 0 ]
  [ "$output" = "em-pass-456" ]
}

@test "cross-provider: export from keychain, import to 1password" {
  # Seed in keychain
  export SECRETS_PROVIDER="keychain"
  secrets set test-agent/token --value "cross-provider-val"

  # Export from keychain
  run secrets export --prefix test-agent
  [ "$status" -eq 0 ]
  local exported="$output"

  # Import to 1password
  run bash -c "printf '%s' '$exported' | SECRETS_PROVIDER=1password secrets import --prefix test-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Imported 1 secret(s)"* ]]

  # Verify in 1password
  export SECRETS_PROVIDER="1password"
  run secrets get test-agent/token
  [ "$status" -eq 0 ]
  [ "$output" = "cross-provider-val" ]
}

# ============================================================
# Error cases
# ============================================================

@test "crud: get nonexistent key fails gracefully" {
  export SECRETS_PROVIDER="keychain"

  run secrets get test-agent/nonexistent
  [ "$status" -ne 0 ]
}

@test "crud: remove nonexistent key fails gracefully" {
  export SECRETS_PROVIDER="keychain"

  run secrets remove test-agent/nonexistent
  [ "$status" -ne 0 ]
}

@test "crud: rename nonexistent key fails gracefully" {
  export SECRETS_PROVIDER="keychain"

  run secrets rename test-agent/nonexistent test-agent/new-name
  [ "$status" -ne 0 ]
}

@test "crud: --provider flag overrides SECRETS_PROVIDER for full lifecycle" {
  # Set SECRETS_PROVIDER to 1password but use --provider keychain
  export SECRETS_PROVIDER="1password"

  secrets set test-agent/override-key --value "via-flag" --provider keychain

  # Should be in keychain, not 1password
  run secrets get test-agent/override-key --provider keychain
  [ "$status" -eq 0 ]
  [ "$output" = "via-flag" ]

  # Should NOT be in 1password
  run secrets get test-agent/override-key
  [ "$status" -ne 0 ]
}
