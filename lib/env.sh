#!/usr/bin/env bash
# Environment variable provider library.
#
# Source this file to get env_get function.
# Reads secrets from environment variables.
#
# Transformation: uppercase, replace anything non-alphanumeric with _.
#   github-pat       → GITHUB_PAT
#   c0da/github-pat  → C0DA_GITHUB_PAT
#   api_key          → API_KEY
#
# Usage:
#   source "$LIB_DIR/env.sh"
#   env_get "github-pat"
#   env_get "c0da/github-pat"

# Retrieve a secret from environment variables.
# Usage: env_get <key>
env_get() {
  local key="$1"

  if [ -z "$key" ]; then
    echo "ERROR: empty key" >&2
    return 1
  fi

  local var_name
  var_name=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g')

  # Bash identifiers must start with a letter or underscore.
  # Keys that transform to digit-leading names (e.g. "1password-key" → "1PASSWORD_KEY")
  # can't be used as env var names.
  if [[ "$var_name" =~ ^[0-9] ]]; then
    echo "ERROR: key '$key' produces invalid env var name '$var_name' (starts with a digit)" >&2
    return 1
  fi

  # Intentionally treats empty-string values the same as unset —
  # an empty secret is a misconfiguration.
  local value="${!var_name:-}"
  if [ -z "$value" ]; then
    echo "ERROR: env var $var_name is empty or not set (derived from key '$key')" >&2
    return 1
  fi
  printf '%s' "$value"
}
