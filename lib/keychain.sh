#!/usr/bin/env bash
# macOS Keychain provider library.
#
# Source this file to get keychain_get, keychain_set, and keychain_list functions.
# Configurable via:
#   SECRETS_SERVICE_PREFIX — keychain service name prefix (default: "secrets/")
#   SECRETS_KEYCHAIN_ACCOUNT — keychain account name (default: "secrets")
#   SECURITY               — path to security binary (default: "security")
#
# Naming convention:
#   Account: "${SECRETS_KEYCHAIN_ACCOUNT}" (fixed)
#   Service: "${SECRETS_SERVICE_PREFIX}<key>"  (e.g., "secrets/baby-joel/github-pat")
#
# Usage:
#   source "$LIB_DIR/keychain.sh"
#   keychain_get "baby-joel/github-pat"
#   echo "my-token" | keychain_set "baby-joel/github-pat"

: "${SECURITY:=security}"
: "${SECRETS_SERVICE_PREFIX:=secrets/}"
: "${SECRETS_KEYCHAIN_ACCOUNT:=secrets}"

keychain_check() {
  if ! command -v "$SECURITY" &>/dev/null; then
    echo "ERROR: macOS 'security' command not found (not on macOS?)" >&2
    return 1
  fi
}

# Retrieve a secret from macOS Keychain.
# Usage: keychain_get <key>
# Outputs the decrypted value to stdout.
keychain_get() {
  local key="$1"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  keychain_check || return 1

  local encoded
  encoded=$("$SECURITY" find-generic-password -a "$SECRETS_KEYCHAIN_ACCOUNT" -s "$service" -w 2>/dev/null) || {
    echo "ERROR: No keychain entry found for key=$key" >&2
    echo "       Store with: secrets set $key" >&2
    return 1
  }

  # Decode base64 (we encode on set to avoid macOS hex-mangling of multi-line values).
  printf '%s' "$encoded" | base64 --decode
}

# Store a secret in macOS Keychain.
# Usage: keychain_set <key> [value]
# If value is not provided, reads from stdin.
keychain_set() {
  local key="$1" value="${2:-}"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  keychain_check || return 1

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

  # Base64-encode to avoid macOS Keychain hex-encoding multi-line values
  local encoded
  encoded=$(printf '%s' "$value" | base64)

  # -U updates if exists, creates if not
  "$SECURITY" add-generic-password -a "$SECRETS_KEYCHAIN_ACCOUNT" -s "$service" -w "$encoded" -U 2>/dev/null

  echo "Stored: key=$key (service=$service)"
}

# List all keychain entries, optionally filtered by prefix.
# Usage: keychain_list [prefix]
keychain_list() {
  local prefix="${1:-}"

  keychain_check || return 1

  local keys
  keys=$(_keychain_discover_keys "$prefix")

  if [ -z "$keys" ]; then
    echo "  (no secrets found${prefix:+ for prefix $prefix})"
    return 0
  fi

  while IFS= read -r key; do
    echo "  ✓ $key"
  done <<< "$keys"
}

# Delete a secret from macOS Keychain.
# Usage: keychain_delete <key>
keychain_delete() {
  local key="$1"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  keychain_check || return 1

  "$SECURITY" delete-generic-password -a "$SECRETS_KEYCHAIN_ACCOUNT" -s "$service" &>/dev/null || {
    echo "ERROR: No keychain entry found for key=$key" >&2
    return 1
  }

  echo "Deleted: key=$key (service=$service)"
}

# Rename a secret in macOS Keychain.
# Usage: keychain_rename <old-key> <new-key>
# Reads the old key, writes it under the new name, then deletes the old entry.
keychain_rename() {
  local old_key="$1" new_key="$2"

  keychain_check || return 1

  if [ "$old_key" = "$new_key" ]; then
    echo "ERROR: Old and new key names are the same: $old_key" >&2
    return 1
  fi

  # Read the existing value
  local value
  value=$(keychain_get "$old_key") || return 1

  # Write under the new name
  keychain_set "$new_key" "$value" || return 1

  # Delete the old entry
  keychain_delete "$old_key" || {
    echo "WARNING: Renamed value is stored under new key, but failed to delete old key=$old_key" >&2
    return 1
  }

  echo "Renamed: key=$old_key → $new_key"
}

# Discover all keys stored in keychain, optionally filtered by prefix.
# Usage: _keychain_discover_keys [prefix]
# If prefix is given, filters to keys starting with "<prefix>/" and strips the prefix.
# Outputs one key name per line.
_keychain_discover_keys() {
  local prefix="${1:-}"
  local dump
  dump=$("$SECURITY" dump-keychain 2>/dev/null) || return 0

  local svc_prefix="$SECRETS_SERVICE_PREFIX"
  local account="$SECRETS_KEYCHAIN_ACCOUNT"

  if [ -n "$prefix" ]; then
    local full_prefix="${svc_prefix}${prefix}/"
    echo "$dump" | awk -v full_prefix="$full_prefix" -v account="$account" '
      function emit() {
        if (svc ~ "^" full_prefix && acct == account) {
          print substr(svc, length(full_prefix) + 1)
        }
        svc=""; acct=""
      }
      /^class:/ { emit() }
      /\"svce\"<blob>=/ { gsub(/.*<blob>="/, ""); gsub(/".*/, ""); svc=$0 }
      /\"acct\"<blob>=/ { gsub(/.*<blob>="/, ""); gsub(/".*/, ""); acct=$0 }
      END { emit() }
    ' | sort
  else
    echo "$dump" | awk -v svc_prefix="$svc_prefix" -v account="$account" '
      function emit() {
        if (svc ~ "^" svc_prefix && acct == account) {
          print substr(svc, length(svc_prefix) + 1)
        }
        svc=""; acct=""
      }
      /^class:/ { emit() }
      /\"svce\"<blob>=/ { gsub(/.*<blob>="/, ""); gsub(/".*/, ""); svc=$0 }
      /\"acct\"<blob>=/ { gsub(/.*<blob>="/, ""); gsub(/".*/, ""); acct=$0 }
      END { emit() }
    ' | sort
  fi
}
