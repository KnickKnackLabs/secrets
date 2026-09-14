#!/usr/bin/env bash
# Check before starting a pipeline consumer so an absent input cannot create a key.
secrets_require_input() {
  if [ -z "${usage_value:-}" ] && [ -t 0 ]; then
    echo "ERROR: No value provided. Pipe the value via stdin." >&2
    return 1
  fi
}

secrets_input() {
  if [ -n "${usage_value:-}" ]; then
    printf '%s' "$usage_value"
  else
    cat
  fi
}
