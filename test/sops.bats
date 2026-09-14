#!/usr/bin/env bats
# Real SOPS and real Mise, with public fake identities and disposable vaults.
load helpers

setup() {
  setup_test_env
  chmod 700 "$TEST_DIR"
  export SECRETS_PROVIDER=sops
  export SECRETS_SOPS_BINARY
  SECRETS_SOPS_BINARY="$(mise -C "$REPO_DIR" which sops)"
  cp "$REPO_DIR/test/fixtures/sops/identity.txt" "$SECRETS_SOPS_AGE_KEY_FILE"
  chmod 600 "$SECRETS_SOPS_AGE_KEY_FILE"
  export SECRETS_SOPS_RECIPIENT
  SECRETS_SOPS_RECIPIENT="$(< "$REPO_DIR/test/fixtures/sops/recipient.txt")"
}

@test "sops public CRUD preserves exact value bytes and prefix routing" {
  printf 'FAKE-SOPS-SENTINEL\nUnicode: café\n\n' > "$TEST_DIR/expected"
  secrets set demo/first < "$TEST_DIR/expected"
  ! grep -q 'FAKE-SOPS-SENTINEL' "$SECRETS_SOPS_FILE"
  secrets get demo/first > "$TEST_DIR/actual"
  cmp "$TEST_DIR/expected" "$TEST_DIR/actual"
  secrets rename demo/first demo/second
  secrets get demo/second > "$TEST_DIR/actual"
  cmp "$TEST_DIR/expected" "$TEST_DIR/actual"
  run secrets list --prefix demo/
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo/second"* ]]
  [[ "$output" != *"demo/first"* ]]
  run secrets list --prefix other/
  [ "$status" -eq 0 ]
  [[ "$output" != *"demo/second"* ]]
  secrets remove demo/second
  run secrets get demo/second
  [ "$status" -ne 0 ]
}

@test "sops JSON import export preserves strings and merges once" {
  printf '%s' '{"demo/multiline":"line\n\n","quoted":"\"word\"","empty":"","nul":"a\u0000b"}' > "$TEST_DIR/input.json"
  secrets import < "$TEST_DIR/input.json"
  secrets export > "$TEST_DIR/output.json"
  diff <(jq -S . "$TEST_DIR/input.json") <(jq -S . "$TEST_DIR/output.json")
  printf '%s' '{"demo/another":"fake"}' | secrets import
  run secrets export --prefix demo/
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq length)" -eq 2 ]
}

@test "sops invalid import and rename collision leave original ciphertext unchanged" {
  printf '%s' '{"one":"fake1","two":"fake2"}' | secrets import
  cp "$SECRETS_SOPS_FILE" "$TEST_DIR/before"
  run secrets rename one two
  [ "$status" -ne 0 ]
  cmp "$TEST_DIR/before" "$SECRETS_SOPS_FILE"
  printf '%s' '{"one":"first","one":"second"}' > "$TEST_DIR/invalid.json"
  run secrets import < "$TEST_DIR/invalid.json"
  [ "$status" -ne 0 ]
  cmp "$TEST_DIR/before" "$SECRETS_SOPS_FILE"
}

@test "sops failed executable diagnostics do not expose values or replace vault" {
  printf '%s' 'fake-original' | secrets set demo/key
  cp "$SECRETS_SOPS_FILE" "$TEST_DIR/before"
  printf '#!/bin/sh\nprintf FAKE-DIAGNOSTIC-SECRET >&2\nexit 1\n' > "$MOCK_BIN/failing-sops"
  chmod +x "$MOCK_BIN/failing-sops"
  export SECRETS_SOPS_BINARY="$MOCK_BIN/failing-sops"
  run secrets get demo/key
  [ "$status" -ne 0 ]
  [[ "$output" != *"FAKE-DIAGNOSTIC-SECRET"* ]]
  cmp "$TEST_DIR/before" "$SECRETS_SOPS_FILE"
}

@test "sops filesystem and authenticated-encryption invariants" {
  run python3 "$REPO_DIR/test/sops_invariants.py"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
