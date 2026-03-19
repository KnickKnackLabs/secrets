#!/usr/bin/env bash
# macOS Keychain provider library.
#
# Source this file to get keychain_get, keychain_set, and keychain_list functions.
# Configurable via:
#   SECRETS_SERVICE_PREFIX — keychain service name prefix (default: "secrets/")
#   SECURITY               — path to security binary (default: "security")
#
# Naming convention:
#   Account: "<agent>"
#   Service: "${SECRETS_SERVICE_PREFIX}<key>"  (e.g., "secrets/github-pat")
#
# Usage:
#   source "$LIB_DIR/keychain.sh"
#   keychain_get "baby-joel" "github-pat"
#   echo "my-token" | keychain_set "baby-joel" "github-pat"

: "${SECURITY:=security}"
: "${SECRETS_SERVICE_PREFIX:=secrets/}"

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

# List all keychain entries for an agent (or all agents).
# Usage: keychain_list [agent]
# Discovers keys dynamically by scanning keychain for the service prefix.
keychain_list() {
  local agent="${1:-}"

  keychain_check || return 1

  if [ -n "$agent" ]; then
    # Dump keychain entries and find services matching our prefix for this agent
    local keys
    keys=$(_keychain_discover_keys "$agent")

    if [ -z "$keys" ]; then
      echo "  (no secrets found for $agent)"
      return 0
    fi

    while IFS= read -r key; do
      echo "  ✓ $key"
    done <<< "$keys"
  else
    # No agent specified — show all agents and their keys
    local dump
    dump=$("$SECURITY" dump-keychain 2>/dev/null) || return 0

    local prefix="$SECRETS_SERVICE_PREFIX"
    # Extract unique (service, account) pairs.
    # NOTE: field ordering within a block is not guaranteed by macOS.
    echo "$dump" | awk -v prefix="$prefix" '
      function emit() {
        if (svc ~ "^" prefix) {
          key = substr(svc, length(prefix) + 1)
          print "  " key ": " acct
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

# Discover all keys stored for a given agent.
# Usage: _keychain_discover_keys <agent>
# Outputs one key name per line.
_keychain_discover_keys() {
  local agent="$1"
  local dump
  dump=$("$SECURITY" dump-keychain 2>/dev/null) || return 0

  local prefix="$SECRETS_SERVICE_PREFIX"
  # NOTE: macOS dump-keychain does not guarantee field ordering within an entry.
  # "acct" may appear before or after "svce". Collect both per block, emit at
  # block boundary (next "class:" line or EOF).
  echo "$dump" | awk -v prefix="$prefix" -v agent="$agent" '
    function emit() {
      if (svc ~ "^" prefix && acct == agent) {
        print substr(svc, length(prefix) + 1)
      }
      svc=""; acct=""
    }
    /^class:/ { emit() }
    /\"svce\"<blob>=/ { gsub(/.*<blob>="/, ""); gsub(/".*/, ""); svc=$0 }
    /\"acct\"<blob>=/ { gsub(/.*<blob>="/, ""); gsub(/".*/, ""); acct=$0 }
    END { emit() }
  ' | sort
}
