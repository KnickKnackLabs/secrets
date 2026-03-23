#!/usr/bin/env bash
# Mock 1Password CLI (op) binary and seed helpers.

create_mock_op() {
  cat > "$MOCK_BIN/op" <<'MOCK'
#!/usr/bin/env bash
# Mock 1Password CLI — file-backed store simulation.
# Flat naming: $MOCK_OP_STORE/<vault>/<title>/value
# Where title is the full key (e.g., "baby-joel/github-pat")

cmd_item_get() {
  local title="$1" vault="" field="" format=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="$2"; shift 2 ;;
      --fields) field="$2"; shift 2 ;;
      --reveal) shift ;;
      --format) format="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  vault="${vault:-Agents}"
  # No --fields: check if item (directory) exists at all
  if [ -z "$field" ]; then
    if [ -d "$MOCK_OP_STORE/$vault/$title" ]; then
      printf '{"title":"%s"}' "$title"
      return 0
    else
      echo "[ERROR] 2024/01/01 00:00:00 \"$title\" isn't a item in \"$vault\"" >&2
      return 1
    fi
  fi
  local file="$MOCK_OP_STORE/$vault/$title/$field"
  if [ -f "$file" ]; then
    local value
    value=$(cat "$file")
    if [ "$format" = "json" ]; then
      printf '{"value":"%s"}' "$value"
    else
      printf '%s' "$value"
    fi
    return 0
  else
    echo "[ERROR] 2024/01/01 00:00:00 \"$title\" isn't a item in \"$vault\"" >&2
    return 1
  fi
}

cmd_item_edit() {
  local title="$1" vault="" assignment=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="$2"; shift 2 ;;
      *=*) assignment="$1"; shift ;;
      *) shift ;;
    esac
  done
  vault="${vault:-Agents}"
  local field_raw="${assignment%%=*}"
  local value="${assignment#*=}"
  local field="${field_raw%%\[*}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/$field"
}

cmd_item_create() {
  local vault="" category="" title="" assignment=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="$2"; shift 2 ;;
      --category) category="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      *=*) assignment="$1"; shift ;;
      *) shift ;;
    esac
  done
  vault="${vault:-Agents}"
  local field_raw="${assignment%%=*}"
  local value="${assignment#*=}"
  local field="${field_raw%%\[*}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/$field"
}

cmd_item_delete() {
  local title="$1" vault=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  vault="${vault:-Agents}"
  if [ -d "$MOCK_OP_STORE/$vault/$title" ]; then
    rm -rf "$MOCK_OP_STORE/$vault/$title"
    return 0
  else
    echo "[ERROR] 2024/01/01 00:00:00 \"$title\" isn't a item in \"$vault\"" >&2
    return 1
  fi
}

cmd_item_list() {
  local vault="" format=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --vault) vault="$2"; shift 2 ;;
      --format) format="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  vault="${vault:-Agents}"
  local vault_dir="$MOCK_OP_STORE/$vault"
  if [ ! -d "$vault_dir" ]; then
    echo "[]"
    return 0
  fi
  # Build JSON array of items from directory structure
  local first=true
  printf '['
  # Find all "value" files and derive item titles from their paths
  while IFS= read -r value_file; do
    local rel="${value_file#$vault_dir/}"
    local title="${rel%/value}"
    if [ "$first" = true ]; then
      first=false
    else
      printf ','
    fi
    printf '{"title":"%s"}' "$title"
  done < <(find "$vault_dir" -name "value" -type f 2>/dev/null | sort)
  printf ']'
}

case "$1" in
  account)
    echo '{"name":"test"}'
    exit 0
    ;;
  item)
    case "$2" in
      get)    shift 2; cmd_item_get "$@" ;;
      edit)   shift 2; cmd_item_edit "$@" ;;
      create) shift 2; cmd_item_create "$@" ;;
      delete) shift 2; cmd_item_delete "$@" ;;
      list)   shift 2; cmd_item_list "$@" ;;
      *)      echo "mock op: unknown item subcommand: $2" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "mock op: unknown command: $1" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/op"
}

# Seed mock 1password with a value.
# Usage: seed_op <key> <plaintext-value>
# Flat naming: vault/key/value
seed_op() {
  local key="$1" value="$2"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  mkdir -p "$MOCK_OP_STORE/$vault/$key"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$key/value"
}

# Seed mock 1password with a legacy structured item.
# Usage: seed_op_legacy <agent> <item_suffix> <field> <plaintext-value>
# Creates: vault/<agent> - <item_suffix>/<field>
seed_op_legacy() {
  local agent="$1" item_suffix="$2" field="$3" value="$4"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  local title="${agent} - ${item_suffix}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/$field"
}
