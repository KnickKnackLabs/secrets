#!/usr/bin/env bash
# Mock secret-tool (libsecret) binary and seed helpers.

create_mock_secret_tool() {
  cat > "$MOCK_BIN/secret-tool" <<'MOCK'
#!/usr/bin/env bash
# Mock secret-tool command — file-backed keyring simulation.
# Stores base64-encoded values in $MOCK_LIBSECRET/<account>/<service>

# Collect "<attr> <value>" pairs into service/account, ignoring flags.
parse_attrs() {
  service=""; account=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --*) shift ;;
      service) service="$2"; shift 2 ;;
      account) account="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
}

main() {
  if [ -n "${MOCK_SECRET_TOOL_DBUS_ERROR:-}" ]; then
    echo 'Cannot autolaunch D-Bus without X11 $DISPLAY' >&2
    return 1
  fi

  local cmd="$1"; shift
  local service account

  case "$cmd" in
    lookup)
      parse_attrs "$@"
      local file="$MOCK_LIBSECRET/$account/$service"
      if [ -f "$file" ]; then
        cat "$file"
        return 0
      else
        return 1
      fi
      ;;

    store)
      parse_attrs "$@"
      local file="$MOCK_LIBSECRET/$account/$service"
      mkdir -p "$(dirname "$file")"
      cat > "$file"
      ;;

    clear)
      parse_attrs "$@"
      local file="$MOCK_LIBSECRET/$account/$service"
      rm -f "$file"
      return 0
      ;;

    search)
      parse_attrs "$@"
      while IFS= read -r secret_file; do
        [ -f "$secret_file" ] || continue
        local rel="${secret_file#$MOCK_LIBSECRET/}"
        local acct="${rel%%/*}"
        local svc="${rel#$acct/}"
        [ -n "$account" ] && [ "$acct" != "$account" ] && continue
        # Real secret-tool splits its output: the item body goes to stdout
        # while the "attribute.*" lines go to stderr. Reproduced faithfully —
        # consumers that discard stderr silently see no attributes at all.
        echo "[/$RANDOM]"
        echo "label = $svc"
        echo "secret = $(cat "$secret_file")"
        [ -n "${MOCK_SECRET_TOOL_SEARCH_INJECT:-}" ] && echo "$MOCK_SECRET_TOOL_SEARCH_INJECT"
        echo "created = 2026-01-01 00:00:00"
        echo "modified = 2026-01-01 00:00:00"
        echo "attribute.account = $acct" >&2
        echo "attribute.service = $svc" >&2
      done < <(find "$MOCK_LIBSECRET" -type f 2>/dev/null | sort)
      # Real secret-tool exits 0 when nothing matches; only a genuine failure
      # is non-zero, and it can fail after already emitting items.
      if [ -n "${MOCK_SECRET_TOOL_SEARCH_ERROR:-}" ]; then
        echo "$MOCK_SECRET_TOOL_SEARCH_ERROR" >&2
        return 1
      fi
      ;;

    *)
      echo "mock secret-tool: unknown command: $cmd" >&2
      return 1
      ;;
  esac
}

main "$@"
MOCK
  chmod +x "$MOCK_BIN/secret-tool"
}

# Seed mock keyring with a value.
# Usage: seed_libsecret <key> <plaintext-value>
seed_libsecret() {
  local key="$1" value="$2"
  local service="${SECRETS_SERVICE_PREFIX}${key}"
  local account="${SECRETS_LIBSECRET_ACCOUNT}"
  local encoded
  encoded=$(printf '%s' "$value" | base64)
  local file="$MOCK_LIBSECRET/$account/$service"
  mkdir -p "$(dirname "$file")"
  printf '%s' "$encoded" > "$file"
}
