#!/usr/bin/env bash
# Test helpers for secrets BATS tests.
#
# Provides:
#   - REPO_DIR, LIB_DIR paths
#   - Mock binary creation (mock_security, mock_op, mock_gpg)
#   - Isolated keychain simulation via mock security binary
#   - Isolated 1password simulation via mock op binary
#   - Isolated GPG simulation via mock gpg binary

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"

# --- Test isolation ---

setup_test_env() {
  export TEST_DIR="$BATS_TEST_TMPDIR/secrets-test-$$"
  export MOCK_BIN="$TEST_DIR/mock-bin"
  export MOCK_KEYCHAIN="$TEST_DIR/keychain"
  export MOCK_OP_STORE="$TEST_DIR/op-store"
  export MOCK_GPG_DIR="$TEST_DIR/gpg"
  mkdir -p "$MOCK_BIN" "$MOCK_KEYCHAIN" "$MOCK_OP_STORE" "$MOCK_GPG_DIR"

  # Use test-specific service prefix to avoid touching real keychain
  export SECRETS_SERVICE_PREFIX="test-secrets/"

  # Point library at mock binaries
  export SECURITY="$MOCK_BIN/security"
  export OP="$MOCK_BIN/op"
  export GPG="$MOCK_BIN/gpg"
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
      local file="$MOCK_KEYCHAIN/$account/$service"
      mkdir -p "$(dirname "$file")"
      printf '%s' "$password" > "$file"
      ;;

    delete-generic-password)
      local account="" service=""
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -a) account="$2"; shift 2 ;;
          -s) service="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      local file="$MOCK_KEYCHAIN/$account/$service"
      if [ -f "$file" ]; then
        rm -f "$file"
        return 0
      else
        echo "security: SecItemDelete: The specified item could not be found in the keychain." >&2
        return 44
      fi
      ;;

    dump-keychain)
      # Find all secret files (may be nested due to / in service names).
      # Output realistic blocks with class: delimiters.
      # Alternates field order to match macOS behavior (acct/svce order varies).
      local _idx=0
      while IFS= read -r secret_file; do
        [ -f "$secret_file" ] || continue
        local rel="${secret_file#$MOCK_KEYCHAIN/}"
        local account="${rel%%/*}"
        local service="${rel#$account/}"
        echo "class: \"genp\""
        echo "attributes:"
        # Alternate field ordering to exercise consumers that assume svce-before-acct
        if (( _idx % 2 == 0 )); then
          echo "    \"svce\"<blob>=\"$service\""
          echo "    \"acct\"<blob>=\"$account\""
        else
          echo "    \"acct\"<blob>=\"$account\""
          echo "    \"svce\"<blob>=\"$service\""
        fi
        _idx=$((_idx + 1))
      done < <(find "$MOCK_KEYCHAIN" -type f 2>/dev/null | sort)
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
# Flat naming: <vault>/<agent>/<key>/value

create_mock_op() {
  cat > "$MOCK_BIN/op" <<'MOCK'
#!/usr/bin/env bash
# Mock 1Password CLI — file-backed store simulation.
# Flat naming: $MOCK_OP_STORE/<vault>/<title>/value
# Where title = "<agent>/<key>"

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
  # Items are directories under vault_dir (may contain slashes in name via subdirs)
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

# --- Mock: GPG ---
# Simulates gpg encrypt/decrypt using base64 (no real crypto).
# Uses a marker prefix to identify "encrypted" data.

create_mock_gpg() {
  cat > "$MOCK_BIN/gpg" <<'MOCK'
#!/usr/bin/env bash
# Mock GPG — uses base64 encoding to simulate encrypt/decrypt.
# No real cryptography — just enough to test the export/import flow.

MARKER="MOCK-GPG-ENCRYPTED:"

main() {
  case "$1" in
    --encrypt|-e)
      # Parse args: --encrypt --armor --recipient <r> (reads stdin)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --armor|-a) shift ;;
          --recipient|-r) shift 2 ;;  # ignore recipient
          --trust-model) shift 2 ;;
          *) shift ;;
        esac
      done
      local plaintext
      plaintext=$(cat)
      printf '%s%s' "$MARKER" "$(printf '%s' "$plaintext" | base64)"
      ;;
    --decrypt|-d)
      # Parse args: --decrypt (reads stdin)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --quiet|-q) shift ;;
          --batch) shift ;;
          --yes) shift ;;
          *) shift ;;
        esac
      done
      local ciphertext
      ciphertext=$(cat)
      if [[ "$ciphertext" != "${MARKER}"* ]]; then
        echo "gpg: decryption failed: No valid data found" >&2
        exit 2
      fi
      local encoded="${ciphertext#$MARKER}"
      printf '%s' "$encoded" | base64 --decode
      ;;
    --list-keys)
      # Pretend we have the requested key
      echo "pub   ed25519 2024-01-01 [SC]"
      echo "      ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234"
      echo "uid           [ultimate] Test Agent <test@example.com>"
      ;;
    *)
      echo "mock gpg: unknown command: $1" >&2
      exit 1
      ;;
  esac
}

main "$@"
MOCK
  chmod +x "$MOCK_BIN/gpg"
}

# --- Convenience: seed mock keychain with a value ---
# Usage: seed_keychain <agent> <key> <plaintext-value>
seed_keychain() {
  local agent="$1" key="$2" value="$3"
  local service="${SECRETS_SERVICE_PREFIX}${key}"
  local encoded
  encoded=$(printf '%s' "$value" | base64)
  local file="$MOCK_KEYCHAIN/$agent/$service"
  mkdir -p "$(dirname "$file")"
  printf '%s' "$encoded" > "$file"
}

# --- Convenience: seed mock 1password with a value ---
# Usage: seed_op <agent> <key> <plaintext-value>
# Flat naming: vault/agent/key/value
seed_op() {
  local agent="$1" key="$2" value="$3"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  local title="${agent}/${key}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/value"
}

# --- Convenience: seed mock 1password with a legacy structured item ---
# Usage: seed_op_legacy <agent> <item_suffix> <field> <plaintext-value>
# Creates: vault/<agent> - <item_suffix>/<field>
# This mimics the old shimmer naming convention (e.g., "ikma - GPG" with field "Private Key")
seed_op_legacy() {
  local agent="$1" item_suffix="$2" field="$3" value="$4"
  local vault="${SECRETS_1PASSWORD_VAULT:-Agents}"
  local title="${agent} - ${item_suffix}"
  mkdir -p "$MOCK_OP_STORE/$vault/$title"
  printf '%s' "$value" > "$MOCK_OP_STORE/$vault/$title/$field"
}
