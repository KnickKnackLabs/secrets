#!/usr/bin/env bash
# Mock GPG binary for testing export/import.

create_mock_gpg() {
  cat > "$MOCK_BIN/gpg" <<'MOCK'
#!/usr/bin/env bash
# Mock GPG — uses base64 encoding to simulate encrypt/decrypt.
# No real cryptography — just enough to test the export/import flow.

MARKER="MOCK-GPG-ENCRYPTED:"

main() {
  case "$1" in
    --encrypt|-e)
      # Parse args: --encrypt --armor --recipient <r> (reads stdin)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --armor|-a) shift ;;
          --recipient|-r) shift 2 ;;  # ignore recipient
          --trust-model) shift 2 ;;
          *) shift ;;
        esac
      done
      local plaintext
      plaintext=$(cat)
      printf '%s%s' "$MARKER" "$(printf '%s' "$plaintext" | base64)"
      ;;
    --decrypt|-d)
      # Parse args: --decrypt (reads stdin)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --quiet|-q) shift ;;
          --batch) shift ;;
          --yes) shift ;;
          *) shift ;;
        esac
      done
      local ciphertext
      ciphertext=$(cat)
      if [[ "$ciphertext" != "${MARKER}"* ]]; then
        echo "gpg: decryption failed: No valid data found" >&2
        exit 2
      fi
      local encoded="${ciphertext#$MARKER}"
      printf '%s' "$encoded" | base64 --decode
      ;;
    --list-keys)
      # Pretend we have the requested key
      echo "pub   ed25519 2024-01-01 [SC]"
      echo "      ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234"
      echo "uid           [ultimate] Test Agent <test@example.com>"
      ;;
    *)
      echo "mock gpg: unknown command: $1" >&2
      exit 1
      ;;
  esac
}

main "$@"
MOCK
  chmod +x "$MOCK_BIN/gpg"
}
