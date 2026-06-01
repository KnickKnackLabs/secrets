#!/usr/bin/env bats

load helpers

setup() {
  setup_test_env
  create_mock_security
  export SECRETS_PROVIDER=env
}

RFC_SHA1_SECRET="GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

@test "totp generates a 6-digit code from a raw base32 secret" {
  export C0DA_GITHUB_TOTP="$RFC_SHA1_SECRET"

  run secrets totp c0da/github-totp --at 59
  [ "$status" -eq 0 ]
  [ "$output" = "287082" ]
}

@test "totp generates an otpauth URI code with URI digits" {
  export C0DA_GITHUB_TOTP="otpauth://totp/GitHub:c0da-ricon?secret=$RFC_SHA1_SECRET&issuer=GitHub&digits=8&period=30"

  run secrets totp c0da/github-totp --at 59
  [ "$status" -eq 0 ]
  [ "$output" = "94287082" ]
}

@test "totp validates without printing a code" {
  export C0DA_GITHUB_TOTP="otpauth://totp/GitHub:c0da-ricon?secret=$RFC_SHA1_SECRET&issuer=GitHub"

  run secrets totp c0da/github-totp --validate
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "totp accepts lowercase and grouped raw secrets" {
  export C0DA_GITHUB_TOTP="gezd gnbv gy3t qojq gezd gnbv gy3t qojq"

  run secrets totp c0da/github-totp --at 59
  [ "$status" -eq 0 ]
  [ "$output" = "287082" ]
}

@test "totp --provider flag selects a storage backend" {
  unset SECRETS_PROVIDER
  seed_keychain "c0da/github-totp" "$RFC_SHA1_SECRET"

  run secrets totp --provider keychain c0da/github-totp --at 59
  [ "$status" -eq 0 ]
  [ "$output" = "287082" ]
}

@test "totp fails closed for invalid stored values without leaking the value" {
  export C0DA_GITHUB_TOTP="not a totp secret!!!"

  run secrets totp c0da/github-totp --at 59
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid TOTP secret or otpauth URI"* ]]
  [[ "$output" != *"not a totp secret"* ]]
}

@test "totp ignores stale inherited usage variables" {
  export C0DA_GITHUB_TOTP="$RFC_SHA1_SECRET"
  export usage_validate=true

  run secrets totp c0da/github-totp --at 59
  [ "$status" -eq 0 ]
  [ "$output" = "287082" ]
}

@test "totp fails without a provider" {
  unset SECRETS_PROVIDER
  export C0DA_GITHUB_TOTP="$RFC_SHA1_SECRET"
  export usage_provider=env

  run secrets totp c0da/github-totp --at 59
  [ "$status" -ne 0 ]
  [[ "$output" == *"No secret provider"* ]]
}
