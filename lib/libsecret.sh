#!/usr/bin/env bash
# libsecret (Linux keyring) provider library.
#
# Source this file to get libsecret_get, libsecret_set, and libsecret_list functions.
# Configurable via:
#   SECRETS_SERVICE_PREFIX    — service attribute prefix (default: "secrets/")
#   SECRETS_LIBSECRET_ACCOUNT — account attribute value (default: "secrets")
#   SECRET_TOOL               — path to secret-tool binary (default: "secret-tool")
#
# Naming convention (mirrors the macOS keychain provider):
#   Attribute "account": "${SECRETS_LIBSECRET_ACCOUNT}" (fixed)
#   Attribute "service": "${SECRETS_SERVICE_PREFIX}<key>"  (e.g., "secrets/baby-joel/github-pat")
#
# Usage:
#   source "$LIB_DIR/libsecret.sh"
#   libsecret_get "baby-joel/github-pat"
#   echo "my-token" | libsecret_set "baby-joel/github-pat"

: "${SECRET_TOOL:=secret-tool}"
: "${SECRETS_SERVICE_PREFIX:=secrets/}"
: "${SECRETS_LIBSECRET_ACCOUNT:=secrets}"

libsecret_check() {
  if ! command -v "$SECRET_TOOL" &>/dev/null; then
    echo "ERROR: 'secret-tool' command not found (install libsecret)." >&2
    echo "       Debian/Ubuntu: apt install libsecret-tools" >&2
    echo "       Arch: pacman -S libsecret" >&2
    return 1
  fi
}

# Retrieve a secret from the login keyring.
# Usage: libsecret_get <key>
# Outputs the decoded value to stdout.
libsecret_get() {
  local key="$1"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  libsecret_check || return 1

  # Capture stderr so a missing keyring daemon isn't reported as a missing key —
  # secret-tool exits 1 for both, and conflating them sends you looking for a
  # secret you did in fact store.
  local encoded err
  err=$(mktemp)
  trap 'rm -f "$err"' RETURN

  encoded=$("$SECRET_TOOL" lookup service "$service" account "$SECRETS_LIBSECRET_ACCOUNT" 2>"$err") || {
    if grep -qi "dbus\|secret service\|org.freedesktop.secrets\|cannot autolaunch" "$err"; then
      echo "ERROR: No running secret service (is gnome-keyring/kwallet started and unlocked?)" >&2
      echo "       secret-tool: $(cat "$err")" >&2
      return 1
    fi
    echo "ERROR: No keyring entry found for key=$key" >&2
    echo "       Store with: secrets set $key" >&2
    return 1
  }

  # An entry with an empty secret is a misconfiguration, not a valid value.
  if [ -z "$encoded" ]; then
    echo "ERROR: Empty value for key=$key in keyring" >&2
    echo "       Service: $service" >&2
    return 1
  fi

  # Decode base64 (we encode on set — see libsecret_set).
  printf '%s' "$encoded" | base64 --decode
}

# Store a secret in the login keyring.
# Usage: libsecret_set <key> [value]
# If value is not provided, reads from stdin.
libsecret_set() {
  local key="$1" value="${2:-}"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  libsecret_check || return 1

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

  # Base64-encode to match the keychain provider, so values round-trip
  # identically through either local backend and multi-line secrets don't
  # depend on how the backend treats a trailing newline.
  local encoded
  encoded=$(printf '%s' "$value" | base64)

  # `store` is an upsert — it replaces the secret on matching attributes.
  printf '%s' "$encoded" | "$SECRET_TOOL" store \
    --label="${SECRETS_SERVICE_PREFIX}${key}" \
    service "$service" account "$SECRETS_LIBSECRET_ACCOUNT" || {
    echo "ERROR: Failed to store key=$key in keyring" >&2
    return 1
  }

  echo "Stored: key=$key (service=$service)"
}

# List all keyring entries, optionally filtered by prefix.
# Usage: libsecret_list [prefix]
libsecret_list() {
  local prefix="${1:-}"

  libsecret_check || return 1

  local keys
  keys=$(_libsecret_discover_keys "$prefix")

  if [ -z "$keys" ]; then
    echo "  (no secrets found${prefix:+ for prefix $prefix})"
    return 0
  fi

  while IFS= read -r key; do
    echo "  ✓ $key"
  done <<< "$keys"
}

# Delete a secret from the login keyring.
# Usage: libsecret_delete <key>
libsecret_delete() {
  local key="$1"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  libsecret_check || return 1

  # `clear` exits 0 whether or not anything matched, so check existence first.
  "$SECRET_TOOL" lookup service "$service" account "$SECRETS_LIBSECRET_ACCOUNT" &>/dev/null || {
    echo "ERROR: No keyring entry found for key=$key" >&2
    return 1
  }

  "$SECRET_TOOL" clear service "$service" account "$SECRETS_LIBSECRET_ACCOUNT" &>/dev/null || {
    echo "ERROR: Failed to delete key=$key from keyring" >&2
    return 1
  }

  echo "Deleted: key=$key (service=$service)"
}

# Rename a secret in the login keyring.
# Usage: libsecret_rename <old-key> <new-key>
# Reads the old key, writes it under the new name, then deletes the old entry.
libsecret_rename() {
  local old_key="$1" new_key="$2"

  libsecret_check || return 1

  if [ "$old_key" = "$new_key" ]; then
    echo "ERROR: Old and new key names are the same: $old_key" >&2
    return 1
  fi

  # Read the existing value
  local value
  value=$(libsecret_get "$old_key") || return 1

  # Write under the new name
  libsecret_set "$new_key" "$value" || return 1

  # Delete the old entry
  libsecret_delete "$old_key" || {
    echo "WARNING: Renamed value is stored under new key, but failed to delete old key=$old_key" >&2
    return 1
  }

  echo "Renamed: key=$old_key → $new_key"
}

# Discover all keys stored in the keyring, optionally filtered by prefix.
# Usage: _libsecret_discover_keys [prefix]
# Always returns full key paths (e.g., "baby-joel/github-pat").
# If prefix is given, filters to keys starting with the prefix string.
# Outputs one key name per line.
_libsecret_discover_keys() {
  local prefix="${1:-}"

  # Two quirks of `secret-tool search`, both non-obvious:
  #  - it writes the "attribute.*" lines to stderr and the rest to stdout, so
  #    stderr has to be folded in or the only lines we care about vanish;
  #  - it prints the secret itself, unlike macOS `dump-keychain`.
  # Selecting just the service attribute handles both: no secret value ever
  # leaves this function.
  local dump
  dump=$("$SECRET_TOOL" search --all account "$SECRETS_LIBSECRET_ACCOUNT" 2>&1) || return 0

  local match_prefix="${SECRETS_SERVICE_PREFIX}${prefix}"

  echo "$dump" \
    | sed -n 's/^attribute\.service = //p' \
    | awk -v match_prefix="$match_prefix" -v svc_prefix="$SECRETS_SERVICE_PREFIX" '
        index($0, match_prefix) == 1 { print substr($0, length(svc_prefix) + 1) }
      ' \
    | sort
}
