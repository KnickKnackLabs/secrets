#!/usr/bin/env bash
# Fake-only op executable; provider tests inject this absolute path through OP.

create_mock_op() {
  cp "$REPO_DIR/test/helpers/mock_op.py" "$MOCK_BIN/op"
  chmod +x "$MOCK_BIN/op"
}

seed_op() {
  local key="$1" value="$2"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  mkdir -p "$MOCK_OP_STORE/$vault/$key"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$key/value"
}

# Legacy migration fixtures intentionally use the old item and field names.
seed_op_legacy() {
  local agent="$1" item_suffix="$2" field="$3" value="$4"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  local title="${agent} - ${item_suffix}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/$field"
}
