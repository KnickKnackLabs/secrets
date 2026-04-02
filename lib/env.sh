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
  local var_name
  var_name=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g')

  local value="${!var_name:-}"
  if [ -z "$value" ]; then
    echo "ERROR: env var $var_name is not set (derived from key '$key')" >&2
    return 1
  fi
  printf '%s' "$value"
}
