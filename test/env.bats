#!/usr/bin/env bats

load helpers

setup() {
  setup_test_env
  export SECRETS_PROVIDER=env
}

# --- Key transformation ---

@test "env: kebab-case key" {
  export GITHUB_PAT="test-token-123"
  run secrets get "github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "test-token-123" ]
}

@test "env: snake_case key" {
  export GITHUB_PAT="test-token-456"
  run secrets get "github_pat"
  [ "$status" -eq 0 ]
  [ "$output" = "test-token-456" ]
}

@test "env: path key with slash" {
  export C0DA_GITHUB_PAT="agent-token"
  run secrets get "c0da/github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "agent-token" ]
}

@test "env: deeply nested path" {
  export SHARED_KEYS_ANTHROPIC_API_KEY="deep-value"
  run secrets get "shared/keys/anthropic-api-key"
  [ "$status" -eq 0 ]
  [ "$output" = "deep-value" ]
}

@test "env: already uppercase key" {
  export API_KEY="my-api-key"
  run secrets get "API_KEY"
  [ "$status" -eq 0 ]
  [ "$output" = "my-api-key" ]
}

@test "env: mixed case preserved as uppercase" {
  export MY_SECRET_KEY="mixed"
  run secrets get "My-Secret-Key"
  [ "$status" -eq 0 ]
  [ "$output" = "mixed" ]
}

# --- Error cases ---

@test "env: errors when env var not set" {
  unset GITHUB_PAT 2>/dev/null || true
  run secrets get "github-pat"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "GITHUB_PAT"
  echo "$output" | grep -q "not set"
}

@test "env: error message shows derived var name for path keys" {
  unset C0DA_GITHUB_PAT 2>/dev/null || true
  run secrets get "c0da/github-pat"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "C0DA_GITHUB_PAT"
}

# --- Value preservation ---

@test "env: preserves special characters in values" {
  export MY_TOKEN="p@ss w0rd=with/special+chars"
  run secrets get "my-token"
  [ "$status" -eq 0 ]
  [ "$output" = "p@ss w0rd=with/special+chars" ]
}

@test "env: preserves multiline values" {
  export MY_KEY="line1
line2
line3"
  run secrets get "my-key"
  [ "$status" -eq 0 ]
  [ "$output" = "line1
line2
line3" ]
}

# --- Provider dispatch ---

@test "env: --provider flag selects env provider" {
  unset SECRETS_PROVIDER
  export SIMPLE_KEY="via-flag"
  run secrets get --provider env "simple-key"
  [ "$status" -eq 0 ]
  [ "$output" = "via-flag" ]
}
