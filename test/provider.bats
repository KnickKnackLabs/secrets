#!/usr/bin/env bats
# Tests for provider-transparent get/set/list tasks.
# Verifies that SECRETS_PROVIDER dispatches to the correct backend.

load helpers

setup() {
  setup_test_env
  create_mock_security
  create_mock_op

  # Set up mise to run tasks from repo
  export MISE_PROJECT_ROOT="$REPO_DIR"
}

# --- Provider dispatch: keychain ---

@test "get dispatches to keychain when SECRETS_PROVIDER=keychain" {
  export SECRETS_PROVIDER="keychain"
  seed_keychain "test-agent/github-pat" "keychain-token"

  run secrets get test-agent/github-pat
  [ "$status" -eq 0 ]
  [ "$output" = "keychain-token" ]
}

@test "set dispatches to keychain when SECRETS_PROVIDER=keychain" {
  export SECRETS_PROVIDER="keychain"

  run secrets set test-agent/github-pat --value "new-token"
  [ "$status" -eq 0 ]

  run secrets get test-agent/github-pat
  [ "$output" = "new-token" ]
}

# --- Provider dispatch: 1password ---

@test "get dispatches to 1password when SECRETS_PROVIDER=1password" {
  export SECRETS_PROVIDER="1password"
  seed_op "test-agent/github-pat" "op-token"

  run secrets get test-agent/github-pat
  [ "$status" -eq 0 ]
  [ "$output" = "op-token" ]
}

@test "set dispatches to 1password when SECRETS_PROVIDER=1password" {
  export SECRETS_PROVIDER="1password"

  run secrets set test-agent/email-password --value "op-pass"
  [ "$status" -eq 0 ]

  run secrets get test-agent/email-password
  [ "$output" = "op-pass" ]
}

# --- Error handling ---

@test "get fails without SECRETS_PROVIDER" {
  unset SECRETS_PROVIDER

  run secrets get test-agent/github-pat
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "set fails without SECRETS_PROVIDER" {
  unset SECRETS_PROVIDER

  run secrets set test-agent/github-pat --value "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}

@test "get fails with unknown provider" {
  export SECRETS_PROVIDER="vault"

  run secrets get test-agent/github-pat
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown provider"* ]]
}

# --- --provider flag overrides env var ---

@test "--provider flag overrides SECRETS_PROVIDER env var" {
  export SECRETS_PROVIDER="1password"
  seed_keychain "test-agent/github-pat" "keychain-wins"

  run secrets get test-agent/github-pat --provider keychain
  [ "$status" -eq 0 ]
  [ "$output" = "keychain-wins" ]
}

# --- arbitrary keys work through tasks ---

@test "arbitrary key names work through provider-transparent tasks" {
  export SECRETS_PROVIDER="keychain"

  run secrets set test-agent/my-custom-key --value "custom-val"
  [ "$status" -eq 0 ]

  run secrets get test-agent/my-custom-key
  [ "$status" -eq 0 ]
  [ "$output" = "custom-val" ]
}

# --- list requires provider ---

@test "list fails without provider" {
  unset SECRETS_PROVIDER

  run secrets list
  [ "$status" -ne 0 ]
}
