#!/usr/bin/env bash
# macOS Keychain provider library.
#
# Source this file to get keychain_get and keychain_set functions.
# Configurable via:
#   SECRETS_SERVICE_PREFIX — keychain service name prefix (default: "secrets-")
#   SECURITY               — path to security binary (default: "security")
#
# Usage:
#   source "$LIB_DIR/keychain.sh"
#   keychain_get "baby-joel" "github-pat"
#   echo "my-token" | keychain_set "baby-joel" "github-pat"

: "${SECURITY:=security}"
: "${SECRETS_SERVICE_PREFIX:=secrets-}"

keychain_check() {
  if ! command -v "$SECURITY" &>/dev/null; then
    echo "ERROR: macOS 'security' command not found (not on macOS?)" >&2
    return 1
  fi
}

# Retrieve a secret from macOS Keychain.
# Usage: keychain_get <agent> <key>
# Outputs the decrypted value to stdout.
keychain_get() {
  local agent="$1" key="$2"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  keychain_check || return 1

  local encoded
  encoded=$("$SECURITY" find-generic-password -a "$agent" -s "$service" -w 2>/dev/null) || {
    echo "ERROR: No keychain entry found for agent=$agent key=$key" >&2
    echo "       Store with: secrets set $agent $key" >&2
    return 1
  }

  # Decode base64 (we encode on set to avoid macOS hex-mangling of multi-line values).
  printf '%s' "$encoded" | base64 --decode
}

# Store a secret in macOS Keychain.
# Usage: keychain_set <agent> <key> [value]
# If value is not provided, reads from stdin.
keychain_set() {
  local agent="$1" key="$2" value="${3:-}"
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
  "$SECURITY" add-generic-password -a "$agent" -s "$service" -w "$encoded" -U 2>/dev/null

  echo "Stored: agent=$agent key=$key (service=$service)"
}

# List all keychain entries matching the service prefix.
# Usage: keychain_list [agent]
# If agent is provided, shows which keys exist for that agent.
# If omitted, shows all agents per key.
keychain_list() {
  local agent="${1:-}"

  keychain_check || return 1

  # We need the known keys list
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$script_dir/secret-keys.sh"

  if [ -n "$agent" ]; then
    for key in "${KNOWN_SECRET_KEYS[@]}"; do
      local service="${SECRETS_SERVICE_PREFIX}${key}"
      if "$SECURITY" find-generic-password -a "$agent" -s "$service" -w &>/dev/null; then
        echo "  ✓ $key"
      else
        echo "  ✗ $key"
      fi
    done
  else
    for key in "${KNOWN_SECRET_KEYS[@]}"; do
      local service="${SECRETS_SERVICE_PREFIX}${key}"
      local accounts
      accounts=$("$SECURITY" dump-keychain 2>/dev/null | grep -A3 "\"$service\"" | grep "acct" | sed 's/.*<blob>="//' | sed 's/".*//' || true)
      if [ -n "$accounts" ]; then
        echo "  $key: $(echo "$accounts" | tr '\n' ' ')"
      fi
    done
  fi
}
