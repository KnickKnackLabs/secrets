#!/usr/bin/env bash
# Mock macOS security (keychain) binary and seed helpers.

create_mock_security() {
  cat > "$MOCK_BIN/security" <<'MOCK'
#!/usr/bin/env bash
# Mock macOS security command — file-backed keychain simulation.
# Stores base64-encoded values in $MOCK_KEYCHAIN/<account>/<service>

main() {
  case "$1" in
    find-generic-password)
      local account="" service="" want_password=false
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -a) account="$2"; shift 2 ;;
          -s) service="$2"; shift 2 ;;
          -w) want_password=true; shift ;;
          *) shift ;;
        esac
      done
      local file="$MOCK_KEYCHAIN/$account/$service"
      if [ -f "$file" ]; then
        if [ "$want_password" = true ]; then
          cat "$file"
        fi
        return 0
      else
        echo "security: SecItemCopyMatching: The specified item could not be found in the keychain." >&2
        return 44
      fi
      ;;

    add-generic-password)
      local account="" service="" password=""
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -a) account="$2"; shift 2 ;;
          -s) service="$2"; shift 2 ;;
          -w) password="$2"; shift 2 ;;
          -U) shift ;;
          *) shift ;;
        esac
      done
      local file="$MOCK_KEYCHAIN/$account/$service"
      mkdir -p "$(dirname "$file")"
      printf '%s' "$password" > "$file"
      ;;

    delete-generic-password)
      local account="" service=""
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -a) account="$2"; shift 2 ;;
          -s) service="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      local file="$MOCK_KEYCHAIN/$account/$service"
      if [ -f "$file" ]; then
        rm -f "$file"
        return 0
      else
        echo "security: SecItemDelete: The specified item could not be found in the keychain." >&2
        return 44
      fi
      ;;

    dump-keychain)
      # Find all secret files (may be nested due to / in service names).
      # Output realistic blocks with class: delimiters.
      # Alternates field order to match macOS behavior (acct/svce order varies).
      local _idx=0
      while IFS= read -r secret_file; do
        [ -f "$secret_file" ] || continue
        local rel="${secret_file#$MOCK_KEYCHAIN/}"
        local account="${rel%%/*}"
        local service="${rel#$account/}"
        echo "class: \"genp\""
        echo "attributes:"
        # Alternate field ordering to exercise consumers that assume svce-before-acct
        if (( _idx % 2 == 0 )); then
          echo "    \"svce\"<blob>=\"$service\""
          echo "    \"acct\"<blob>=\"$account\""
        else
          echo "    \"acct\"<blob>=\"$account\""
          echo "    \"svce\"<blob>=\"$service\""
        fi
        _idx=$((_idx + 1))
      done < <(find "$MOCK_KEYCHAIN" -type f 2>/dev/null | sort)
      ;;

    *)
      echo "mock security: unknown command: $1" >&2
      return 1
      ;;
  esac
}

main "$@"
MOCK
  chmod +x "$MOCK_BIN/security"
}

# Seed mock keychain with a value.
# Usage: seed_keychain <key> <plaintext-value>
seed_keychain() {
  local key="$1" value="$2"
  local service="${SECRETS_SERVICE_PREFIX}${key}"
  local account="${SECRETS_KEYCHAIN_ACCOUNT}"
  local encoded
  encoded=$(printf '%s' "$value" | base64)
  local file="$MOCK_KEYCHAIN/$account/$service"
  mkdir -p "$(dirname "$file")"
  printf '%s' "$encoded" > "$file"
}
