#!/usr/bin/env bats
# Direct task/provider checks; all 1Password operations use a synthetic CLI.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_DIR MISE_CONFIG_ROOT="$REPO_DIR"
  export OP="$BATS_TEST_TMPDIR/op"
  export OP_CALL_LOG="$BATS_TEST_TMPDIR/op-calls"
  export SECRETS_1PASSWORD_VAULT=Agents
  export usage_provider=1password usage_prefix=test-agent/
  unset FAIL_KEY

  cat > "$OP" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1 $2" >> "$OP_CALL_LOG"
case "$1 $2" in
  'account get') printf '{}\n' ;;
  'item list') printf '[{"title":"test-agent/a"},{"title":"test-agent/b"}]\n' ;;
  'item get')
    [[ "$3" != "${FAIL_KEY:-}" ]] || exit 1
    printf '{"value":"FAKE-VALUE-%s"}\n' "${3##*/}"
    ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$OP"
}

@test "1Password export checks the account once for multiple keys" {
  run bash "$REPO_DIR/.mise/tasks/export"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^account get$' "$OP_CALL_LOG")" -eq 1 ]
  [ "$(grep -c '^item get$' "$OP_CALL_LOG")" -eq 2 ]
  [ "$(printf '%s' "$output" | jq -r '.["test-agent/a"]')" = FAKE-VALUE-a ]
  [ "$(printf '%s' "$output" | jq -r '.["test-agent/b"]')" = FAKE-VALUE-b ]
}

@test "standalone op_get retains its account check" {
  run bash -c 'source "$REPO_DIR/lib/providers/onepassword/provider.sh"; op_get test-agent/a'
  [ "$status" -eq 0 ]
  [ "$output" = FAKE-VALUE-a ]
  [ "$(grep -c '^account get$' "$OP_CALL_LOG")" -eq 1 ]
}

@test "a later read failure still prevents any exported bundle" {
  export FAIL_KEY=test-agent/b
  run bash "$REPO_DIR/.mise/tasks/export"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no bundle emitted"* ]]
  [[ "$output" != *FAKE-VALUE* ]]
  [ "$(grep -c '^account get$' "$OP_CALL_LOG")" -eq 1 ]
}
