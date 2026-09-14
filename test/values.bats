#!/usr/bin/env bats
# Fake-only public CLI value paths, compared as bytes rather than BATS output.

load helpers

setup() {
  setup_test_env
  create_mock_security
  create_mock_op
  printf '"fake SECRET-SENTINEL"\\snowman ☃\nline two\n\n' > "$TEST_DIR/value"
}

@test "1password create update get rename preserve exact bytes without value argv" {
  secrets set agent/key -p 1password < "$TEST_DIR/value"
  secrets set agent/key -p 1password < "$TEST_DIR/value"
  secrets get agent/key -p 1password > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
  secrets rename agent/key agent/renamed -p 1password
  secrets get agent/renamed -p 1password > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
  ! grep -q 'SECRET-SENTINEL\|value\[password\]' "$MOCK_OP_LOG"
}

@test "keychain set get rename preserve exact trailing newlines" {
  secrets set agent/key -p keychain < "$TEST_DIR/value"
  secrets get agent/key -p keychain > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
  secrets rename agent/key agent/renamed -p keychain
  secrets get agent/renamed -p keychain > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
}

@test "cross-provider JSON export import preserves exact strings" {
  secrets set agent/key -p 1password < "$TEST_DIR/value"
  secrets export -p 1password > "$TEST_DIR/bundle.json"
  secrets import -p keychain < "$TEST_DIR/bundle.json"
  secrets get agent/key -p keychain > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
  secrets export -p keychain > "$TEST_DIR/bundle.json"
  secrets import -p 1password < "$TEST_DIR/bundle.json"
  secrets get agent/key -p 1password > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
}

@test "literal null string is a value, not JSON null" {
  printf null > "$TEST_DIR/value"
  secrets set agent/key -p 1password < "$TEST_DIR/value"
  secrets get agent/key -p 1password > "$TEST_DIR/actual"
  cmp "$TEST_DIR/value" "$TEST_DIR/actual"
}

@test "failed inventory never creates and never exposes provider diagnostics" {
  export MOCK_OP_FAIL=list
  run secrets set agent/key -p 1password < "$TEST_DIR/value"
  [ "$status" -ne 0 ]
  [[ "$output" != *SECRET-SENTINEL* ]]
  ! grep -q '"create"\|"edit"' "$MOCK_OP_LOG"
}

@test "failed existing item read never falls back to create" {
  seed_op agent/key old
  export MOCK_OP_FAIL=get
  run secrets set agent/key -p 1password < "$TEST_DIR/value"
  [ "$status" -ne 0 ]
  [[ "$output" != *SECRET-SENTINEL* ]]
  ! grep -q '"create"\|"edit"' "$MOCK_OP_LOG"
}

@test "duplicate titles reject ambiguous writes" {
  seed_op agent/key old
  export MOCK_OP_DUPLICATE=1
  run secrets set agent/key -p 1password < "$TEST_DIR/value"
  [ "$status" -ne 0 ]
  [[ "$output" == *Duplicate* ]]
  ! grep -q '"edit"' "$MOCK_OP_LOG"
}

@test "invalid import types and duplicate names fail before any writes" {
  printf '{"first":"valid", "later":12}' > "$TEST_DIR/bundle.json"
  run secrets import -p 1password < "$TEST_DIR/bundle.json"
  [ "$status" -ne 0 ]
  [ ! -e "$MOCK_OP_LOG" ]
  printf '{"first":"one", "first":"two"}' > "$TEST_DIR/bundle.json"
  run secrets import -p 1password < "$TEST_DIR/bundle.json"
  [ "$status" -ne 0 ]
  [ ! -e "$MOCK_OP_LOG" ]
}

@test "failed legacy import returns failure instead of an all-success receipt" {
  export MOCK_OP_FAIL=create
  printf '{"agent/key":"fake"}' > "$TEST_DIR/bundle.json"
  run secrets import -p 1password < "$TEST_DIR/bundle.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to import"* ]]
  [[ "$output" != *SECRET-SENTINEL* ]]
}
