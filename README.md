<div align="center">

<pre>
  ╔════════════════════════════════╗
  ║  secrets get zeke/github-pat  ║
  ╚════════════════════════════════╝
  keychain ✓ │ libsecret ✓ │ 1password ✓
</pre>

# secrets

**Provider-transparent, name-agnostic secret management for agents.**

One interface, multiple backends. Store and retrieve agent secrets
without knowing — or caring — where they live. Any key name works.

![lang: bash](https://img.shields.io/badge/lang-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![tests: 149 passing](https://img.shields.io/badge/tests-149%20passing-brightgreen?style=flat)](test/)
![providers: 3 backends](https://img.shields.io/badge/providers-3%20backends-blue?style=flat)
![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)

</div>

<br />

## Quick start

```bash
# Install
shiv install secrets

# Store a secret (using macOS Keychain)
export SECRETS_PROVIDER=keychain
secrets set zeke/github-pat --value "ghp_abc123..."

# Retrieve it
secrets get zeke/github-pat

# Generate a TOTP code from a stored otpauth URI or base32 seed
secrets totp zeke/github-totp

# List what's stored
secrets list --prefix zeke

# Transfer secrets between machines
secrets export --prefix zeke | secrets import --provider keychain
```

## How it works

Every secret is addressed by a single **key** (e.g., `zeke/github-pat`). Key names are arbitrary — there's no registry or allowlist. The `SECRETS_PROVIDER` environment variable (or `--provider` flag) determines which backend handles the request.

```
                      secrets get <key>
                            │
                   ┌────────┴────────┐
                   │ SECRETS_PROVIDER │
                   └────────┬────────┘
         ┌─────────┬─────┴─────┬─────────┐
         ▼         ▼           ▼         ▼
   ┌──────────┐┌──────────┐┌──────────┐┌──────────┐
   │ keychain ││ libsecret││ 1password││  (more)  │
   │ (macOS)  ││ (Linux)  ││   (op)   ││  (soon)  │
   └──────────┘└──────────┘└──────────┘└──────────┘
```

The provider is just a storage backend. The interface is always the same: `secrets get <key>` and `secrets set <key>`. Switch providers by changing one env var — no code changes, no data format differences.

<br />

## Commands

### Core

The provider-transparent interface — these dispatch to whichever backend `SECRETS_PROVIDER` points to:


#### secrets export

Export secrets as a JSON bundle (stdout)

```
secrets export [--prefix <prefix>] [-p <provider>]
```

| Flag             | Description                                                                                                         | Default |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- | ------- |
| `--prefix`       | Filter keys by prefix (e.g., baby-joel). Uses startswith matching — include trailing / for exact prefix boundaries. | —       |
| `-p, --provider` | Provider: keychain, libsecret, or 1password (overrides SECRETS_PROVIDER)                                            | —       |


#### secrets get

Retrieve a secret

```
secrets get <key> [-p <provider>]
```

| Flag             | Description                                                                   | Default |
| ---------------- | ----------------------------------------------------------------------------- | ------- |
| `-p, --provider` | Provider: keychain, libsecret, 1password, or env (overrides SECRETS_PROVIDER) | —       |


#### secrets import

Import secrets from a JSON bundle (stdin)

```
secrets import [-p <provider>]
```

| Flag             | Description                                                              | Default |
| ---------------- | ------------------------------------------------------------------------ | ------- |
| `-p, --provider` | Provider: keychain, libsecret, or 1password (overrides SECRETS_PROVIDER) | —       |


#### secrets list

List stored secrets

```
secrets list [--prefix <prefix>] [-p <provider>]
```

| Flag             | Description                                                                                                         | Default |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- | ------- |
| `--prefix`       | Filter keys by prefix (e.g., baby-joel). Uses startswith matching — include trailing / for exact prefix boundaries. | —       |
| `-p, --provider` | Provider: keychain, libsecret, or 1password (overrides SECRETS_PROVIDER)                                            | —       |


#### secrets remove

Remove a secret

```
secrets remove <key> [-p <provider>]
```

| Flag             | Description                                                              | Default |
| ---------------- | ------------------------------------------------------------------------ | ------- |
| `-p, --provider` | Provider: keychain, libsecret, or 1password (overrides SECRETS_PROVIDER) | —       |


#### secrets rename

Rename a secret

```
secrets rename <old-key> <new-key> [-p <provider>]
```

| Flag             | Description                                                              | Default |
| ---------------- | ------------------------------------------------------------------------ | ------- |
| `-p, --provider` | Provider: keychain, libsecret, or 1password (overrides SECRETS_PROVIDER) | —       |


#### secrets set

Store a secret

```
secrets set <key> [-v <value>] [-p <provider>]
```

| Flag             | Description                                                              | Default |
| ---------------- | ------------------------------------------------------------------------ | ------- |
| `-v, --value`    | Value to store (or pipe via stdin)                                       | —       |
| `-p, --provider` | Provider: keychain, libsecret, or 1password (overrides SECRETS_PROVIDER) | —       |


#### secrets totp

Generate a TOTP code from a stored secret

```
secrets totp <key> [-p <provider>] [--at <epoch>] [--validate]
```

| Flag             | Description                                                                   | Default |
| ---------------- | ----------------------------------------------------------------------------- | ------- |
| `-p, --provider` | Provider: keychain, libsecret, 1password, or env (overrides SECRETS_PROVIDER) | —       |
| `--at`           | Unix timestamp to evaluate (for tests/debugging)                              | —       |
| `--validate`     | Validate the stored TOTP secret without printing a code                       | —       |


### Provider-specific

Direct access to a specific backend — no `SECRETS_PROVIDER` needed:


#### secrets 1password:get

Retrieve a secret from 1Password

```
secrets 1password:get <key>
```


#### secrets 1password:set

Store a secret in 1Password

```
secrets 1password:set <key> [-v <value>]
```


#### secrets keychain:get

Retrieve a secret from macOS Keychain

```
secrets keychain:get <key>
```


#### secrets keychain:set

Store a secret in macOS Keychain

```
secrets keychain:set <key> [-v <value>]
```


#### secrets libsecret:get

Retrieve a secret from the Linux keyring

```
secrets libsecret:get <key>
```


#### secrets libsecret:set

Store a secret in the Linux keyring

```
secrets libsecret:set <key> [-v <value>]
```

<br />

## Providers

### macOS Keychain (`keychain`)

Uses the macOS Keychain via the `security` CLI. Values are base64-encoded to handle multi-line secrets (like GPG keys) without corruption.

| Variable                 | Description                  | Default    |
| ------------------------ | ---------------------------- | ---------- |
| `SECRETS_SERVICE_PREFIX` | Keychain service name prefix | `secrets/` |
| `SECURITY`               | Path to security binary      | `security` |

### Linux keyring (`libsecret`)

Uses the Linux login keyring (GNOME Keyring, KWallet, or any Secret Service provider) via the `secret-tool` CLI. The local counterpart to the macOS Keychain provider — values are base64-encoded the same way, so secrets round-trip identically through either.

| Variable                    | Description                | Default       |
| --------------------------- | -------------------------- | ------------- |
| `SECRETS_SERVICE_PREFIX`    | Service attribute prefix   | `secrets/`    |
| `SECRETS_LIBSECRET_ACCOUNT` | Account attribute value    | `secrets`     |
| `SECRET_TOOL`               | Path to secret-tool binary | `secret-tool` |

### 1Password (`1password`)

Uses 1Password via the `op` CLI. Items use flat naming (`<agent>/<key>`) with a single `value` field, stored in a configurable vault.

| Variable                  | Description          | Default  |
| ------------------------- | -------------------- | -------- |
| `SECRETS_1PASSWORD_VAULT` | 1Password vault name | `Agents` |
| `OP`                      | Path to op binary    | `op`     |

<br />

## Testing

```bash
git clone https://github.com/KnickKnackLabs/secrets.git
cd secrets && mise trust && mise install
mise run test
```

**149 tests** across 10 suites, using [BATS](https://github.com/bats-core/bats-core).

External tools (`security`, `secret-tool`, `op`) are mocked via dependency injection — the libraries accept `$SECURITY`, `$SECRET_TOOL` and `$OP` environment variables pointing to mock binaries. Tests run against file-backed simulations of each backend, with full isolation per test case. No real keychain, keyring, or 1Password interaction. TOTP generation uses Python's standard library.

## Library architecture

The code is organized as sourced bash libraries, not monolithic task scripts:

```
secrets/
├── lib/
│   ├── keychain.sh       # macOS Keychain provider (keychain_get, keychain_set, keychain_list)
│   ├── libsecret.sh      # Linux keyring provider (libsecret_get, libsecret_set, libsecret_list)
│   ├── 1password.sh      # 1Password provider (op_get, op_set, op_list)
│   └── totp.py           # TOTP parsing/generation helper
├── .mise/tasks/
│   ├── get               # Provider-transparent get (dispatches via SECRETS_PROVIDER)
│   ├── set               # Provider-transparent set
│   ├── remove            # Provider-transparent remove
│   ├── list              # List stored keys (dynamic discovery)
│   ├── export            # Export all secrets as plain JSON
│   ├── import            # Import secrets from a JSON bundle
│   ├── totp              # Generate TOTP codes from stored secrets
│   ├── migrate           # Migrate 1Password items from structured to flat naming
│   ├── keychain/         # Direct keychain access
│   ├── libsecret/        # Direct keyring access
│   └── 1password/        # Direct 1Password access
└── test/
    ├── helpers.bash       # Mock binaries (security, secret-tool, op) + test isolation
    ├── keychain.bats      # Keychain provider tests
    ├── libsecret.bats     # Linux keyring provider tests
    ├── 1password.bats     # 1Password provider tests
    ├── crud.bats          # End-to-end CRUD integration tests
    ├── delete-rename.bats # Delete and rename operation tests
    ├── provider.bats      # Provider dispatch integration tests
    ├── export-import.bats # Export/import roundtrip tests
    ├── migrate.bats       # 1Password migration tests
    └── totp.bats          # TOTP parsing/generation tests
```

Libraries are sourced by tasks and tests alike — making every function independently testable. The task scripts are thin entry points that parse args, source the right library, and call one function.

<br />

<div align="center">

---

<sub>
One interface. Any backend. Any key.<br />
Your secrets, wherever they need to be.<br />
<br />
This README was generated from <a href="https://github.com/KnickKnackLabs/readme">README.tsx</a>.
</sub></div>
