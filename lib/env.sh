#!/usr/bin/env bash
# Environment variable provider library.
#
# Source this file to get env_get function.
# Reads secrets from environment variables, with optional mapping files
# for keys that don't have a trivial env var name.
#
# Default transformation (simple keys only):
#   - Uppercase the key
#   - Replace hyphens with underscores
#   - Only works for keys containing [a-zA-Z0-9_-]
#   - Keys with other characters (e.g., /) require a mapping
#
# Mapping file format (one per line):
#   <key>=<ENV_VAR_NAME>
#   # Comments and blank lines are ignored
#
# Example:
#   c0da/github-pat=AGENT_GITHUB_PAT
#   shared/anthropic-api-key=ANTHROPIC_API_KEY
#
# Usage:
#   source "$LIB_DIR/env.sh"
#   env_get "github-pat"                              # → looks up $GITHUB_PAT
#   env_get "c0da/github-pat" "agent.map:shared.map"  # → uses mapping files

# Retrieve a secret from environment variables.
# Usage: env_get <key> [mapping_files]
# mapping_files is colon-separated list of mapping file paths.
env_get() {
  local key="$1"
  local mapping_files="${2:-}"

  # Try mapping files first
  if [ -n "$mapping_files" ]; then
    local var_name
    var_name=$(_env_lookup_mapping "$key" "$mapping_files") || true
    if [ -n "$var_name" ]; then
      local value="${!var_name:-}"
      if [ -z "$value" ]; then
        echo "ERROR: Mapping found ($key → $var_name) but env var $var_name is not set" >&2
        return 1
      fi
      printf '%s' "$value"
      return 0
    fi
  fi

  # Fall back to default transformation (simple keys only)
  if [[ "$key" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    local var_name
    var_name=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    local value="${!var_name:-}"
    if [ -z "$value" ]; then
      echo "ERROR: env var $var_name is not set (derived from key '$key')" >&2
      return 1
    fi
    printf '%s' "$value"
    return 0
  fi

  # Key contains characters that can't be trivially mapped
  echo "ERROR: Key '$key' contains characters that can't be mapped to an env var name." >&2
  echo "       Provide a mapping file: secrets get --provider env --mapping <file> \"$key\"" >&2
  return 1
}

# Look up a key in mapping files.
# Returns the env var name if found, empty string if not.
_env_lookup_mapping() {
  local key="$1"
  local mapping_files="$2"

  local IFS=':'
  for file in $mapping_files; do
    [ -f "$file" ] || continue
    while IFS= read -r line; do
      # Skip comments and blank lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      # Parse key=VAR_NAME
      local map_key="${line%%=*}"
      local map_var="${line#*=}"
      if [ "$map_key" = "$key" ]; then
        printf '%s' "$map_var"
        return 0
      fi
    done < "$file"
  done

  return 1
}
