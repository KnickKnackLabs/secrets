#!/usr/bin/env bash
# 1Password provider library.
#
# Source this file to get op_get, op_set, and op_list functions.
# Configurable via:
#   OP                      — path to 1Password CLI binary (default: "op")
#   SECRETS_1PASSWORD_VAULT  — vault name (default: "Agents")
#
# Naming convention (flat):
#   Item title: "<key>"     (e.g., "baby-joel/github-pat")
#   Field:      "value"
#   Category:   "Secure Note"
#
# Usage:
#   source "$LIB_DIR/providers/onepassword/provider.sh"
#   op_get "baby-joel/github-pat"
#   echo "my-token" | op_set "baby-joel/github-pat"

: "${OP:=op}"

SECRETS_1PASSWORD_VAULT="${SECRETS_1PASSWORD_VAULT:-Agents}"

op_check() {
  if ! command -v "$OP" &>/dev/null; then
    echo "ERROR: 1Password CLI (op) not found." >&2
    echo "       Install from: https://developer.1password.com/docs/cli" >&2
    return 1
  fi

  if ! "$OP" account get &>/dev/null; then
    echo "ERROR: Not signed in to 1Password. Run: op signin" >&2
    return 1
  fi
}

# Retrieve a secret from 1Password.
# Usage: op_get <key>
# Outputs the value to stdout.
op_get() {
  local key="$1"

  op_check || return 1

  # Only JSON is captured; jq emits the value exactly, without adding a newline.
  # Provider diagnostics and malformed output may contain secrets.
  local op_output
  op_output=$("$OP" item get "$key" --vault "$SECRETS_1PASSWORD_VAULT" --fields value --reveal --format json 2>/dev/null) || {
    echo "ERROR: Failed to retrieve key=$key from 1Password; check the item and authentication." >&2
    return 1
  }
  printf '%s' "$op_output" | jq -e '.value | type == "string" and length > 0' >/dev/null 2>&1 || {
    echo "ERROR: Missing or empty string value in 1Password." >&2
    return 1
  }
  printf '%s' "$op_output" | jq -jr '.value' 2>/dev/null
}

# Store a secret in 1Password.
# Usage: op_set <key> [value]
# If value is not provided, reads from stdin.
op_set() {
  local key="$1" lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  op_check || return 1
  if [ -n "${2:-}" ]; then
    printf '%s' "$2" | OP="$OP" SECRETS_1PASSWORD_VAULT="$SECRETS_1PASSWORD_VAULT" PYTHONPATH="$lib_dir" python3 -m providers.onepassword.write "$key"
  elif [ -t 0 ]; then
    echo "ERROR: No value provided. Pipe the value via stdin." >&2
    return 1
  else
    OP="$OP" SECRETS_1PASSWORD_VAULT="$SECRETS_1PASSWORD_VAULT" PYTHONPATH="$lib_dir" python3 -m providers.onepassword.write "$key"
  fi
}

# Delete a secret from 1Password.
# Usage: op_delete <key>
op_delete() {
  local key="$1"

  op_check || return 1

  "$OP" item delete "$key" --vault "$SECRETS_1PASSWORD_VAULT" < /dev/null &>/dev/null || {
    echo "ERROR: Failed to delete item $key from 1Password (vault=$SECRETS_1PASSWORD_VAULT)" >&2
    return 1
  }

  echo "Deleted: key=$key"
}

# Rename a secret in 1Password.
# Usage: op_rename <old-key> <new-key>
# Reads the old key, creates a new item, then deletes the old one.
op_rename() {
  local old_key="$1" new_key="$2"

  op_check || return 1

  if [ "$old_key" = "$new_key" ]; then
    echo "ERROR: Old and new key names are the same: $old_key" >&2
    return 1
  fi

  # Read the existing value
  local value_json
  value_json=$(set -o pipefail; op_get "$old_key" | jq -Rs '.') || return 1

  # JSON capture preserves trailing newlines and embedded NUL without secret argv.
  printf '%s' "$value_json" | jq -jr '.' | op_set "$new_key" || return 1

  # Delete the old item
  op_delete "$old_key" || {
    echo "WARNING: Renamed value is stored under new key, but failed to delete old key=$old_key" >&2
    return 1
  }

  echo "Renamed: key=$old_key → $new_key"
}

# List 1Password secrets.
# Usage: op_list [prefix]
# If prefix is given, only shows keys starting with the prefix string.
op_list() {
  local prefix="${1:-}"

  op_check || return 1

  local keys
  keys=$(_op_discover_keys "$prefix") || return 1

  if [ -z "$keys" ]; then
    echo "  (no secrets found${prefix:+ for prefix $prefix})"
    return 0
  fi

  while IFS= read -r key; do
    echo "  ✓ $key"
  done <<< "$keys"
}

# Discover all keys stored in 1Password.
# Usage: _op_discover_keys [prefix]
# Always returns full key paths (e.g., "baby-joel/github-pat").
# If prefix is given, filters to keys starting with the prefix string.
# Outputs one key name per line.
_op_discover_keys() {
  local prefix="${1:-}"

  local items
  items=$("$OP" item list --vault "$SECRETS_1PASSWORD_VAULT" --format json 2>/dev/null) || {
    echo "ERROR: Failed to list items from 1Password vault=$SECRETS_1PASSWORD_VAULT" >&2
    return 1
  }

  if [ -n "$prefix" ]; then
    echo "$items" | jq -r --arg prefix "$prefix" '
      .[] | select(.title | startswith($prefix)) | .title
    ' 2>/dev/null | sort
  else
    echo "$items" | jq -r '.[].title' 2>/dev/null | sort
  fi
}
