#!/usr/bin/env bash
# 1Password provider library.
#
# Source this file to get op_get and op_set functions.
# Configurable via:
#   OP — path to 1Password CLI binary (default: "op")
#
# Requires lib/secret-keys.sh to be sourced first (for resolve_key).
#
# Usage:
#   source "$LIB_DIR/secret-keys.sh"
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

  if ! resolve_key "$key"; then
    echo "ERROR: Unknown key: $key" >&2
    echo "       Known keys: $(print_known_keys)" >&2
    return 1
  fi

  local item="${agent} - ${OP_ITEM_SUFFIX}"

  # Capture op output and exit code separately to distinguish failure modes
  local op_stderr op_output op_exit
  op_stderr=$(mktemp)
  trap 'rm -f "$op_stderr"' RETURN

  op_output=$("$OP" item get "$item" --vault "$SECRETS_1PASSWORD_VAULT" --fields "$OP_FIELD_GET" --reveal --format json 2>"$op_stderr") || {
    op_exit=$?
    local op_err
    op_err=$(cat "$op_stderr")

    if echo "$op_err" | grep -qi "isn't a item\|not found\|does not exist\|no item"; then
      echo "ERROR: Item not found in 1Password: $item (vault=$SECRETS_1PASSWORD_VAULT)" >&2
      echo "       Create it with: secrets set $agent $key" >&2
    elif echo "$op_err" | grep -qi "not currently signed in\|session expired\|unauthorized\|authentication"; then
      echo "ERROR: 1Password authentication failed. Run: op signin" >&2
    else
      echo "ERROR: op item get failed (exit $op_exit) for key=$key agent=$agent" >&2
      echo "       Item: $item / Field: $OP_FIELD_GET" >&2
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
    echo "       Item: $item / Field: $OP_FIELD_GET" >&2
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

  if ! resolve_key "$key"; then
    echo "ERROR: Unknown key: $key" >&2
    echo "       Known keys: $(print_known_keys)" >&2
    return 1
  fi

  local item="${agent} - ${OP_ITEM_SUFFIX}"

  # Try edit first (item exists); fall back to create (item doesn't exist)
  # Note: op reads stdin for JSON when it detects a pipe, so close stdin (< /dev/null)
  if "$OP" item get "$item" --vault "$SECRETS_1PASSWORD_VAULT" < /dev/null &>/dev/null; then
    "$OP" item edit "$item" --vault "$SECRETS_1PASSWORD_VAULT" "${OP_FIELD_SET}=${value}" < /dev/null >/dev/null || {
      echo "ERROR: Failed to update key=$key for agent=$agent in 1Password" >&2
      echo "       Item: $item / Field: $OP_FIELD_SET" >&2
      return 1
    }
  else
    "$OP" item create --vault "$SECRETS_1PASSWORD_VAULT" \
      --category "$OP_ITEM_CATEGORY" \
      --title "$item" \
      "${OP_FIELD_SET}=${value}" < /dev/null >/dev/null || {
      echo "ERROR: Failed to create item for key=$key agent=$agent in 1Password" >&2
      echo "       Item: $item / Category: $OP_ITEM_CATEGORY" >&2
      return 1
    }
  fi

  echo "Stored: agent=$agent key=$key (1Password: $item)"
}

# List 1Password secrets for an agent.
# Usage: op_list [agent]
op_list() {
  local agent="${1:-}"

  op_check || return 1

  if [ -z "$agent" ]; then
    echo "  (specify an agent name to check stored keys)"
    return 0
  fi

  for key in "${KNOWN_SECRET_KEYS[@]}"; do
    if resolve_key "$key"; then
      local item="${agent} - ${OP_ITEM_SUFFIX}"
      if "$OP" item get "$item" --vault "$SECRETS_1PASSWORD_VAULT" --fields "$OP_FIELD_GET" --reveal &>/dev/null; then
        echo "  ✓ $key"
      else
        echo "  ✗ $key"
      fi
    fi
  done
}
