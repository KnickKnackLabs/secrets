#!/usr/bin/env bash

: "${SECRET_TOOL:=secret-tool}"
: "${SECRETS_SERVICE_PREFIX:=secrets/}"
: "${SECRETS_LIBSECRET_ACCOUNT:=secrets}"

_libsecret_is_service_unavailable() {
  grep -qi "dbus\|secret service\|org.freedesktop.secrets\|cannot autolaunch" "$1"
}

libsecret_check() {
  if ! command -v "$SECRET_TOOL" &>/dev/null; then
    echo "ERROR: 'secret-tool' command not found (install libsecret)." >&2
    echo "       Debian/Ubuntu: apt install libsecret-tools" >&2
    echo "       Arch: pacman -S libsecret" >&2
    return 1
  fi
}

libsecret_get() {
  local key="$1"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  libsecret_check || return 1

  local encoded lookup_stderr
  lookup_stderr=$(mktemp)
  trap 'rm -f "$lookup_stderr"' RETURN

  encoded=$("$SECRET_TOOL" lookup service "$service" account "$SECRETS_LIBSECRET_ACCOUNT" 2>"$lookup_stderr") || {
    if _libsecret_is_service_unavailable "$lookup_stderr"; then
      echo "ERROR: No running secret service (is gnome-keyring/kwallet started and unlocked?)" >&2
      echo "       secret-tool: $(cat "$lookup_stderr")" >&2
      return 1
    fi
    echo "ERROR: No keyring entry found for key=$key" >&2
    echo "       Store with: secrets set $key" >&2
    return 1
  }

  if [ -z "$encoded" ]; then
    echo "ERROR: Empty value for key=$key in keyring" >&2
    echo "       Service: $service" >&2
    return 1
  fi

  printf '%s' "$encoded" | base64 --decode
}

libsecret_set() {
  local key="$1" value="${2:-}"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  libsecret_check || return 1

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

  local encoded
  encoded=$(printf '%s' "$value" | base64)

  printf '%s' "$encoded" | "$SECRET_TOOL" store \
    --label="${SECRETS_SERVICE_PREFIX}${key}" \
    service "$service" account "$SECRETS_LIBSECRET_ACCOUNT" || {
    echo "ERROR: Failed to store key=$key in keyring" >&2
    return 1
  }

  echo "Stored: key=$key (service=$service)"
}

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

libsecret_delete() {
  local key="$1"
  local service="${SECRETS_SERVICE_PREFIX}${key}"

  libsecret_check || return 1

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

libsecret_rename() {
  local old_key="$1" new_key="$2"

  libsecret_check || return 1

  if [ "$old_key" = "$new_key" ]; then
    echo "ERROR: Old and new key names are the same: $old_key" >&2
    return 1
  fi

  local value
  value=$(libsecret_get "$old_key") || return 1

  libsecret_set "$new_key" "$value" || return 1

  libsecret_delete "$old_key" || {
    echo "WARNING: Renamed value is stored under new key, but failed to delete old key=$old_key" >&2
    return 1
  }

  echo "Renamed: key=$old_key → $new_key"
}

_libsecret_discover_keys() {
  local prefix="${1:-}"

  local search_output_including_stderr
  search_output_including_stderr=$("$SECRET_TOOL" search --all account "$SECRETS_LIBSECRET_ACCOUNT" 2>&1) || return 0

  local match_prefix="${SECRETS_SERVICE_PREFIX}${prefix}"

  echo "$search_output_including_stderr" \
    | sed -n 's/^attribute\.service = //p' \
    | awk -v match_prefix="$match_prefix" -v svc_prefix="$SECRETS_SERVICE_PREFIX" '
        index($0, match_prefix) == 1 { print substr($0, length(svc_prefix) + 1) }
      ' \
    | sort
}
