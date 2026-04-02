#!/usr/bin/env bats

load helpers

setup() {
  setup_test_env
  export SECRETS_PROVIDER=env
}

# --- Simple key transformation ---

@test "env: simple key maps to uppercase env var" {
  export GITHUB_PAT="test-token-123"
  run secrets get "github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "test-token-123" ]
}

@test "env: underscore key maps to uppercase env var" {
  export GITHUB_PAT="test-token-456"
  run secrets get "github_pat"
  [ "$status" -eq 0 ]
  [ "$output" = "test-token-456" ]
}

@test "env: already uppercase key works" {
  export API_KEY="my-api-key"
  run secrets get "API_KEY"
  [ "$status" -eq 0 ]
  [ "$output" = "my-api-key" ]
}

@test "env: simple key errors when env var not set" {
  unset GITHUB_PAT 2>/dev/null || true
  run secrets get "github-pat"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "GITHUB_PAT"
  echo "$output" | grep -q "not set"
}

# --- Path keys require mapping ---

@test "env: path key without mapping errors" {
  run secrets get "c0da/github-pat"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "can't be mapped"
  echo "$output" | grep -q "mapping"
}

# --- Mapping files ---

@test "env: mapping file resolves path key" {
  export AGENT_GITHUB_PAT="mapped-token"
  local mapfile="$TEST_DIR/agent.map"
  echo "c0da/github-pat=AGENT_GITHUB_PAT" > "$mapfile"

  run secrets get --mapping "$mapfile" "c0da/github-pat"
  [ "$status" -eq 0 ]
  [ "$output" = "mapped-token" ]
}

@test "env: mapping file with comments and blank lines" {
  export MY_SECRET="secret-value"
  local mapfile="$TEST_DIR/test.map"
  cat > "$mapfile" <<EOF
# This is a comment
some/key=UNUSED_VAR

  # Another comment
c0da/my-secret=MY_SECRET
EOF

  run secrets get --mapping "$mapfile" "c0da/my-secret"
  [ "$status" -eq 0 ]
  [ "$output" = "secret-value" ]
}

@test "env: mapping found but env var not set errors" {
  unset AGENT_GITHUB_PAT 2>/dev/null || true
  local mapfile="$TEST_DIR/agent.map"
  echo "c0da/github-pat=AGENT_GITHUB_PAT" > "$mapfile"

  run secrets get --mapping "$mapfile" "c0da/github-pat"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "AGENT_GITHUB_PAT"
  echo "$output" | grep -q "not set"
}

@test "env: multiple mapping files, second file matches" {
  export SHARED_API_KEY="shared-key-value"
  local agent_map="$TEST_DIR/agent.map"
  local shared_map="$TEST_DIR/shared.map"
  echo "c0da/github-pat=AGENT_GITHUB_PAT" > "$agent_map"
  echo "shared/api-key=SHARED_API_KEY" > "$shared_map"

  run secrets get --mapping "$agent_map" --mapping "$shared_map" "shared/api-key"
  [ "$status" -eq 0 ]
  [ "$output" = "shared-key-value" ]
}

@test "env: first mapping file takes precedence" {
  export FIRST_VALUE="from-first"
  export SECOND_VALUE="from-second"
  local map1="$TEST_DIR/first.map"
  local map2="$TEST_DIR/second.map"
  echo "my/key=FIRST_VALUE" > "$map1"
  echo "my/key=SECOND_VALUE" > "$map2"

  run secrets get --mapping "$map1" --mapping "$map2" "my/key"
  [ "$status" -eq 0 ]
  [ "$output" = "from-first" ]
}

@test "env: mapping not found falls back to default for simple keys" {
  export SIMPLE_KEY="fallback-value"
  local mapfile="$TEST_DIR/agent.map"
  echo "other/key=OTHER_VAR" > "$mapfile"

  run secrets get --mapping "$mapfile" "simple-key"
  [ "$status" -eq 0 ]
  [ "$output" = "fallback-value" ]
}

@test "env: mapping not found errors for path keys" {
  local mapfile="$TEST_DIR/agent.map"
  echo "other/key=OTHER_VAR" > "$mapfile"

  run secrets get --mapping "$mapfile" "unmapped/key"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "can't be mapped"
}

@test "env: missing mapping file is silently skipped" {
  export SIMPLE_KEY="works-fine"
  run secrets get --mapping "/nonexistent/path.map" "simple-key"
  [ "$status" -eq 0 ]
  [ "$output" = "works-fine" ]
}

# --- Edge cases ---

@test "env: preserves value with special characters" {
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
