#!/usr/bin/env bash
# 1Password provider library.
#
# Source this file to get op_get, op_set, and op_list functions.
# Configurable via:
#   OP                      — path to 1Password CLI binary (default: "op")
#   SECRETS_1PASSWORD_VAULT  — vault name (default: "Agents")
#
# Naming convention (flat, name-agnostic):
#   Item title: "<agent>/<key>"    (e.g., "baby-joel/github-pat")
#   Field:      "value"
#   Category:   "Secure Note"
#
# Usage:
#   source "$LIB_DIR/1password.sh"
#   op_get "baby-joel" "github-pat"
#   echo "my-token" | op_set "baby-joel" "github-pat"

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
# Usage: op_get <agent> <key>
# Outputs the value to stdout.
op_get() {
  local agent="$1" key="$2"

  op_check || return 1

  local item="${agent}/${key}"

  # Capture op output and exit code separately to distinguish failure modes
  local op_stderr op_output
  op_stderr=$(mktemp)
  trap 'rm -f "$op_stderr"' RETURN

  op_output=$("$OP" item get "$item" --vault "$SECRETS_1PASSWORD_VAULT" --fields "value" --reveal --format json 2>"$op_stderr") || {
    local op_exit=$?
    local op_err
    op_err=$(cat "$op_stderr")

    if echo "$op_err" | grep -qi "isn't a item\|not found\|does not exist\|no item"; then
      echo "ERROR: Item not found in 1Password: $item (vault=$SECRETS_1PASSWORD_VAULT)" >&2
      echo "       Create it with: secrets set $agent $key" >&2
    elif echo "$op_err" | grep -qi "not currently signed in\|session expired\|unauthorized\|authentication"; then
      echo "ERROR: 1Password authentication failed. Run: op signin" >&2
    else
      echo "ERROR: op item get failed (exit $op_exit) for key=$key agent=$agent" >&2
      echo "       Item: $item" >&2
      [ -n "$op_err" ] && echo "       op stderr: $op_err" >&2
    fi
    return 1
  }

  local value
  value=$(echo "$op_output" | jq -r '.value' 2>/dev/null) || {
    echo "ERROR: Failed to parse op output as JSON for key=$key agent=$agent" >&2
    echo "       Raw output: $op_output" >&2
    return 1
  }

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "ERROR: Empty value for key=$key agent=$agent in 1Password" >&2
    echo "       Item: $item" >&2
    return 1
  fi

  printf '%s' "$value"
}

# Store a secret in 1Password.
# Usage: op_set <agent> <key> [value]
# If value is not provided, reads from stdin.
op_set() {
  local agent="$1" key="$2" value="${3:-}"

  op_check || return 1

  # Read from stdin if no value provided
  if [ -z "$value" ]; then
    if [ -t 0 ]; then
      echo "ERROR: No value provided. Pass as argument or pipe via stdin." >&2
      return 1
    fi
    value=$(cat)
  fi

  if [ -z "$value" ]; then
    echo "ERROR: Empty value." >&2
    return 1
  fi

  local item="${agent}/${key}"

  # Try edit first (item exists); fall back to create (item doesn't exist)
  # Note: op reads stdin for JSON when it detects a pipe, so close stdin (< /dev/null)
  if "$OP" item get "$item" --vault "$SECRETS_1PASSWORD_VAULT" < /dev/null &>/dev/null; then
    "$OP" item edit "$item" --vault "$SECRETS_1PASSWORD_VAULT" "value[password]=${value}" < /dev/null >/dev/null || {
      echo "ERROR: Failed to update key=$key for agent=$agent in 1Password" >&2
      echo "       Item: $item" >&2
      return 1
    }
  else
    "$OP" item create --vault "$SECRETS_1PASSWORD_VAULT" \
      --category "Secure Note" \
      --title "$item" \
      "value[password]=${value}" < /dev/null >/dev/null || {
      echo "ERROR: Failed to create item for key=$key agent=$agent in 1Password" >&2
      echo "       Item: $item" >&2
      return 1
    }
  fi

  echo "Stored: agent=$agent key=$key (1Password: $item)"
}

# Delete a secret from 1Password.
# Usage: op_delete <agent> <key>
op_delete() {
  local agent="$1" key="$2"

  op_check || return 1

  local item="${agent}/${key}"

  "$OP" item delete "$item" --vault "$SECRETS_1PASSWORD_VAULT" < /dev/null &>/dev/null || {
    echo "ERROR: Failed to delete item $item from 1Password (vault=$SECRETS_1PASSWORD_VAULT)" >&2
    return 1
  }

  echo "Deleted: agent=$agent key=$key (1Password: $item)"
}

# Rename a secret in 1Password.
# Usage: op_rename <agent> <old-key> <new-key>
# Reads the old key, creates a new item, then deletes the old one.
op_rename() {
  local agent="$1" old_key="$2" new_key="$3"

  op_check || return 1

  if [ "$old_key" = "$new_key" ]; then
    echo "ERROR: Old and new key names are the same: $old_key" >&2
    return 1
  fi

  # Read the existing value
  local value
  value=$(op_get "$agent" "$old_key") || return 1

  # Write under the new name
  op_set "$agent" "$new_key" "$value" || return 1

  # Delete the old item
  op_delete "$agent" "$old_key" || {
    echo "WARNING: Renamed value is stored under new key, but failed to delete old key=$old_key" >&2
    return 1
  }

  echo "Renamed: agent=$agent key=$old_key → $new_key"
}

# List 1Password secrets for an agent.
# Usage: op_list [agent]
# Discovers keys dynamically by listing items with the agent prefix.
op_list() {
  local agent="${1:-}"

  op_check || return 1

  if [ -z "$agent" ]; then
    echo "  (specify an agent name to check stored keys)"
    return 0
  fi

  local keys
  keys=$(_op_discover_keys "$agent") || return 1

  if [ -z "$keys" ]; then
    echo "  (no secrets found for $agent)"
    return 0
  fi

  while IFS= read -r key; do
    echo "  ✓ $key"
  done <<< "$keys"
}

# Discover all keys stored for a given agent.
# Usage: _op_discover_keys <agent>
# Outputs one key name per line.
_op_discover_keys() {
  local agent="$1"

  local items
  items=$("$OP" item list --vault "$SECRETS_1PASSWORD_VAULT" --format json 2>/dev/null) || {
    echo "ERROR: Failed to list items from 1Password vault=$SECRETS_1PASSWORD_VAULT" >&2
    return 1
  }

  local prefix="${agent}/"
  echo "$items" | jq -r --arg prefix "$prefix" '
    .[] | select(.title | startswith($prefix)) | .title | ltrimstr($prefix)
  ' 2>/dev/null | sort
}
