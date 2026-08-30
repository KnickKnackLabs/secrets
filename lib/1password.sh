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
#   source "$LIB_DIR/1password.sh"
#   op_get "baby-joel/github-pat"
#   echo "my-token" | op_set "baby-joel/github-pat"

: "${OP:=op}"

SECRETS_1PASSWORD_VAULT="${SECRETS_1PASSWORD_VAULT:-Agents}"

# Recognise an authentication failure in op's stderr.
#
# This exists so the real call can report a sign-in problem, which is why
# op_check no longer probes with `op account get`. Under desktop-app
# integration op authorizes the *calling process*, and a shell pipeline is a
# new process every time, so the approval cannot be cached — a probe before
# every operation simply doubles the authorization dialogs the user sees.
_op_auth_error() {
  printf '%s' "$1" | grep -qi "not currently signed in\|session expired\|unauthorized\|authentication\|no account found"
}

_op_not_found_error() {
  printf '%s' "$1" | grep -qi "isn't a item\|isn't an item\|not found\|does not exist\|no item"
}

op_check() {
  if ! command -v "$OP" &>/dev/null; then
    echo "ERROR: 1Password CLI (op) not found." >&2
    echo "       Install from: https://developer.1password.com/docs/cli" >&2
    return 1
  fi
}

# Retrieve a secret from 1Password.
# Usage: op_get <key>
# Outputs the value to stdout.
op_get() {
  local key="$1"

  op_check || return 1

  # Capture op output and exit code separately to distinguish failure modes
  local op_stderr op_output
  op_stderr=$(mktemp)
  trap 'rm -f "$op_stderr"' RETURN

  op_output=$("$OP" item get "$key" --vault "$SECRETS_1PASSWORD_VAULT" --fields "value" --reveal --format json 2>"$op_stderr") || {
    local op_exit=$?
    local op_err
    op_err=$(cat "$op_stderr")

    if _op_not_found_error "$op_err"; then
      echo "ERROR: Item not found in 1Password: $key (vault=$SECRETS_1PASSWORD_VAULT)" >&2
      echo "       Create it with: secrets set $key" >&2
    elif _op_auth_error "$op_err"; then
      echo "ERROR: 1Password authentication failed. Run: op signin" >&2
    else
      echo "ERROR: op item get failed (exit $op_exit) for key=$key" >&2
      echo "       Item: $key" >&2
      [ -n "$op_err" ] && echo "       op stderr: $op_err" >&2
    fi
    return 1
  }

  local value
  value=$(echo "$op_output" | jq -r '.value' 2>/dev/null) || {
    echo "ERROR: Failed to parse op output as JSON for key=$key" >&2
    echo "       Raw output: $op_output" >&2
    return 1
  }

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "ERROR: Empty value for key=$key in 1Password" >&2
    echo "       Item: $key" >&2
    return 1
  fi

  printf '%s' "$value"
}

# Store a secret in 1Password.
# Usage: op_set <key> [value]
# If value is not provided, reads from stdin.
op_set() {
  local key="$1" value="${2:-}"

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

  # Try edit first, and create only if edit reports the item does not exist.
  # An `op item get` existence probe would be a third separately-authorized op
  # invocation for what is one logical write; edit's own error tells us the
  # same thing. Only a genuine not-found falls through to create, so an edit
  # that failed for any other reason cannot silently produce a duplicate item.
  # Note: op reads stdin for JSON when it detects a pipe, so close stdin (< /dev/null)
  local op_stderr op_err
  op_stderr=$(mktemp)
  trap 'rm -f "$op_stderr"' RETURN

  if ! "$OP" item edit "$key" --vault "$SECRETS_1PASSWORD_VAULT" "value[password]=${value}" < /dev/null >/dev/null 2>"$op_stderr"; then
    op_err=$(cat "$op_stderr")

    if _op_auth_error "$op_err"; then
      echo "ERROR: 1Password authentication failed. Run: op signin" >&2
      return 1
    fi

    if ! _op_not_found_error "$op_err"; then
      echo "ERROR: Failed to update key=$key in 1Password" >&2
      [ -n "$op_err" ] && echo "       op stderr: $op_err" >&2
      return 1
    fi

    "$OP" item create --vault "$SECRETS_1PASSWORD_VAULT" \
      --category "Secure Note" \
      --title "$key" \
      "value[password]=${value}" < /dev/null >/dev/null 2>"$op_stderr" || {
      op_err=$(cat "$op_stderr")
      if _op_auth_error "$op_err"; then
        echo "ERROR: 1Password authentication failed. Run: op signin" >&2
      else
        echo "ERROR: Failed to create item for key=$key in 1Password" >&2
        [ -n "$op_err" ] && echo "       op stderr: $op_err" >&2
      fi
      return 1
    }
  fi

  echo "Stored: key=$key"
}

# Delete a secret from 1Password.
# Usage: op_delete <key>
op_delete() {
  local key="$1"

  op_check || return 1

  local op_stderr op_err
  op_stderr=$(mktemp)
  trap 'rm -f "$op_stderr"' RETURN

  "$OP" item delete "$key" --vault "$SECRETS_1PASSWORD_VAULT" < /dev/null >/dev/null 2>"$op_stderr" || {
    op_err=$(cat "$op_stderr")
    if _op_auth_error "$op_err"; then
      echo "ERROR: 1Password authentication failed. Run: op signin" >&2
    else
      echo "ERROR: Failed to delete item $key from 1Password (vault=$SECRETS_1PASSWORD_VAULT)" >&2
    fi
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
  local value
  value=$(op_get "$old_key") || return 1

  # Write under the new name
  op_set "$new_key" "$value" || return 1

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

  local items op_stderr op_err
  op_stderr=$(mktemp)
  trap 'rm -f "$op_stderr"' RETURN

  items=$("$OP" item list --vault "$SECRETS_1PASSWORD_VAULT" --format json 2>"$op_stderr") || {
    op_err=$(cat "$op_stderr")
    if _op_auth_error "$op_err"; then
      echo "ERROR: 1Password authentication failed. Run: op signin" >&2
    else
      echo "ERROR: Failed to list items from 1Password vault=$SECRETS_1PASSWORD_VAULT" >&2
    fi
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
