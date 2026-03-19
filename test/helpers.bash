#!/usr/bin/env bash
# Test helpers for secrets BATS tests.
#
# Provides:
#   - REPO_DIR, LIB_DIR paths
#   - Mock binary creation (mock_security, mock_op)
#   - Isolated keychain simulation via mock security binary
#   - Isolated 1password simulation via mock op binary

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"

# --- Test isolation ---

setup_test_env() {
  export TEST_DIR="$BATS_TEST_TMPDIR/secrets-test-$$"
  export MOCK_BIN="$TEST_DIR/mock-bin"
  export MOCK_KEYCHAIN="$TEST_DIR/keychain"
  export MOCK_OP_STORE="$TEST_DIR/op-store"
  mkdir -p "$MOCK_BIN" "$MOCK_KEYCHAIN" "$MOCK_OP_STORE"

  # Use test-specific service prefix to avoid touching real keychain
  export SECRETS_SERVICE_PREFIX="test-secrets-"

  # Point library at mock binaries
  export SECURITY="$MOCK_BIN/security"
  export OP="$MOCK_BIN/op"
}

# --- Mock: macOS security (keychain) ---
# Simulates keychain using flat files in $MOCK_KEYCHAIN.
# Files named: <account>/<service>

create_mock_security() {
  cat > "$MOCK_BIN/security" <<'MOCK'
#!/usr/bin/env bash
# Mock macOS security command — file-backed keychain simulation.
# Stores base64-encoded values in $MOCK_KEYCHAIN/<account>/<service>

main() {
  case "$1" in
    find-generic-password)
      local account="" service="" want_password=false
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -a) account="$2"; shift 2 ;;
          -s) service="$2"; shift 2 ;;
          -w) want_password=true; shift ;;
          *) shift ;;
        esac
      done
      local file="$MOCK_KEYCHAIN/$account/$service"
      if [ -f "$file" ]; then
        if [ "$want_password" = true ]; then
          cat "$file"
        fi
        return 0
      else
        echo "security: SecItemCopyMatching: The specified item could not be found in the keychain." >&2
        return 44
      fi
      ;;

    add-generic-password)
      local account="" service="" password=""
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -a) account="$2"; shift 2 ;;
          -s) service="$2"; shift 2 ;;
          -w) password="$2"; shift 2 ;;
          -U) shift ;;
          *) shift ;;
        esac
      done
      mkdir -p "$MOCK_KEYCHAIN/$account"
      printf '%s' "$password" > "$MOCK_KEYCHAIN/$account/$service"
      ;;

    dump-keychain)
      local account_dir account service_file service
      for account_dir in "$MOCK_KEYCHAIN"/*/; do
        [ -d "$account_dir" ] || continue
        account=$(basename "$account_dir")
        for service_file in "$account_dir"/*; do
          [ -f "$service_file" ] || continue
          service=$(basename "$service_file")
          echo "keychain: \"/path/to/keychain\""
          echo "    \"svce\"<blob>=\"$service\""
          echo "    \"acct\"<blob>=\"$account\""
          echo "    ----"
        done
      done
      ;;

    *)
      echo "mock security: unknown command: $1" >&2
      return 1
      ;;
  esac
}

main "$@"
MOCK
  chmod +x "$MOCK_BIN/security"
}

# --- Mock: 1Password CLI (op) ---
# Simulates op using flat files in $MOCK_OP_STORE.
# Files named: <vault>/<item-title>/<field-name>

create_mock_op() {
  cat > "$MOCK_BIN/op" <<'MOCK'
#!/usr/bin/env bash
# Mock 1Password CLI — file-backed store simulation.
# Stores values in $MOCK_OP_STORE/<vault>/<title>/<field>

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

# --- Convenience: seed mock keychain with a value ---
# Usage: seed_keychain <agent> <key> <plaintext-value>
seed_keychain() {
  local agent="$1" key="$2" value="$3"
  local service="${SECRETS_SERVICE_PREFIX}${key}"
  local encoded
  encoded=$(printf '%s' "$value" | base64)
  mkdir -p "$MOCK_KEYCHAIN/$agent"
  printf '%s' "$encoded" > "$MOCK_KEYCHAIN/$agent/$service"
}

# --- Convenience: seed mock 1password with a value ---
# Usage: seed_op <agent> <key> <plaintext-value>
# Requires secret-keys.sh to be sourced for resolve_key.
seed_op() {
  local agent="$1" key="$2" value="$3"
  source "$LIB_DIR/secret-keys.sh"
  resolve_key "$key" || { echo "Unknown key: $key" >&2; return 1; }
  local title="${agent} - ${OP_ITEM_SUFFIX}"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/$OP_FIELD_GET"
}
