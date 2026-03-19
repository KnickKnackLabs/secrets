#!/usr/bin/env bats
# Tests for lib/secret-keys.sh — key registry and resolution.

load helpers

setup() {
  source "$LIB_DIR/secret-keys.sh"
}

# --- KNOWN_SECRET_KEYS ---

@test "KNOWN_SECRET_KEYS contains github-pat" {
  [[ " ${KNOWN_SECRET_KEYS[*]} " == *" github-pat "* ]]
}

@test "KNOWN_SECRET_KEYS contains gpg-private-key" {
  [[ " ${KNOWN_SECRET_KEYS[*]} " == *" gpg-private-key "* ]]
}

@test "KNOWN_SECRET_KEYS contains email-password" {
  [[ " ${KNOWN_SECRET_KEYS[*]} " == *" email-password "* ]]
}

@test "KNOWN_SECRET_KEYS has at least 10 entries" {
  [ "${#KNOWN_SECRET_KEYS[@]}" -ge 10 ]
}

# --- resolve_key ---

@test "resolve_key sets OP_ITEM_SUFFIX for github-pat" {
  resolve_key "github-pat"
  [ "$OP_ITEM_SUFFIX" = "GitHub" ]
}

@test "resolve_key sets OP_FIELD_GET for github-pat" {
  resolve_key "github-pat"
  [ "$OP_FIELD_GET" = "PAT" ]
}

@test "resolve_key sets OP_FIELD_SET with type annotation for github-pat" {
  resolve_key "github-pat"
  [ "$OP_FIELD_SET" = "PAT[password]" ]
}

@test "resolve_key sets OP_ITEM_CATEGORY for github-pat" {
  resolve_key "github-pat"
  [ "$OP_ITEM_CATEGORY" = "login" ]
}

@test "resolve_key handles gpg-private-key (Secure Note category)" {
  resolve_key "gpg-private-key"
  [ "$OP_ITEM_SUFFIX" = "GPG" ]
  [ "$OP_FIELD_GET" = "Private Key" ]
  [ "$OP_ITEM_CATEGORY" = "Secure Note" ]
}

@test "resolve_key handles b2-application-key" {
  resolve_key "b2-application-key"
  [ "$OP_ITEM_SUFFIX" = "B2" ]
  [ "$OP_FIELD_GET" = "Application Key" ]
}

@test "resolve_key returns 1 for unknown key" {
  run resolve_key "nonexistent-key"
  [ "$status" -eq 1 ]
}

# --- print_known_keys ---

@test "print_known_keys outputs comma-separated list" {
  run print_known_keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"github-pat"* ]]
  [[ "$output" == *","* ]]
}
