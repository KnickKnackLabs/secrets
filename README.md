<div align="center">

<pre>
  ╔═══════════════════════════════╗
  ║  secrets get zeke github-pat  ║
  ╚═══════════════════════════════╝
     keychain ✓  │  1password ✓
</pre>

# secrets

**Provider-transparent, name-agnostic secret management for agents.**

One interface, multiple backends. Store and retrieve agent secrets
without knowing — or caring — where they live. Any key name works.

![lang: bash](https://img.shields.io/badge/lang-bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![tests: 56 passing](https://img.shields.io/badge/tests-56%20passing-brightgreen?style=flat)](test/)
![providers: 2 backends](https://img.shields.io/badge/providers-2%20backends-blue?style=flat)
![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)

</div>

<br />

## Quick start

```bash
# Install
shiv install secrets

# Store a secret (using macOS Keychain)
export SECRETS_PROVIDER=keychain
secrets set zeke github-pat --value "ghp_abc123..."

# Retrieve it
secrets get zeke github-pat

# List what's stored
secrets list zeke

# Transfer secrets between machines
secrets export zeke | secrets import zeke --provider keychain
```

## How it works

Every secret is addressed by **agent name** + **key name**. Key names are arbitrary — there's no registry or allowlist. The `SECRETS_PROVIDER` environment variable (or `--provider` flag) determines which backend handles the request.

```
                    secrets get <agent> <key>
                            │
                   ┌────────┴────────┐
                   │ SECRETS_PROVIDER │
                   └────────┬────────┘
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ keychain │ │ 1password│ │  (more)  │
        │ (macOS)  │ │   (op)   │ │  (soon)  │
        └──────────┘ └──────────┘ └──────────┘
```

The provider is just a storage backend. The interface is always the same: `secrets get <agent> <key>` and `secrets set <agent> <key>`. Switch providers by changing one env var — no code changes, no data format differences.

<br />

## Commands

### Core

The provider-transparent interface — these dispatch to whichever backend `SECRETS_PROVIDER` points to:


#### secrets export

Export all secrets for an agent as a GPG-encrypted JSON bundle

```
secrets export <agent> [-p <provider>] [--encrypt-to <recipient>]
```

| Flag | Description | Default |
| --- | --- | --- |
| `-p, --provider` | Provider: keychain or 1password (overrides SECRETS_PROVIDER) | — |
| `--encrypt-to` | GPG recipient (default: <agent>@ricon.family) | — |


#### secrets get

Retrieve a secret for an agent

```
secrets get <agent> <key> [-p <provider>]
```

| Flag | Description | Default |
| --- | --- | --- |
| `-p, --provider` | Provider: keychain or 1password (overrides SECRETS_PROVIDER) | — |


#### secrets import

Import secrets for an agent from a GPG-encrypted JSON bundle (stdin)

```
secrets import <agent> [-p <provider>]
```

| Flag | Description | Default |
| --- | --- | --- |
| `-p, --provider` | Provider: keychain or 1password (overrides SECRETS_PROVIDER) | — |


#### secrets list

List stored secrets for an agent

```
secrets list [agent] [-p <provider>]
```

| Flag | Description | Default |
| --- | --- | --- |
| `-p, --provider` | Provider: keychain or 1password (overrides SECRETS_PROVIDER) | — |


#### secrets set

Store a secret for an agent

```
secrets set <agent> <key> [-v <value>] [-p <provider>]
```

| Flag | Description | Default |
| --- | --- | --- |
| `-v, --value` | Value to store (or pipe via stdin) | — |
| `-p, --provider` | Provider: keychain or 1password (overrides SECRETS_PROVIDER) | — |


### Provider-specific

Direct access to a specific backend — no `SECRETS_PROVIDER` needed:


#### secrets 1password:get

Retrieve a secret from 1Password

```
secrets 1password:get <agent> <key>
```


#### secrets 1password:set

Store a secret in 1Password

```
secrets 1password:set <agent> <key> [-v <value>]
```


#### secrets keychain:get

Retrieve a secret from macOS Keychain

```
secrets keychain:get <agent> <key>
```


#### secrets keychain:set

Store a secret in macOS Keychain

```
secrets keychain:set <agent> <key> [-v <value>]
```

<br />

## Providers

### macOS Keychain (`keychain`)

Uses the macOS Keychain via the `security` CLI. Values are base64-encoded to handle multi-line secrets (like GPG keys) without corruption.

| Variable | Description | Default |
| --- | --- | --- |
| `SECRETS_SERVICE_PREFIX` | Keychain service name prefix | `secrets/` |
| `SECURITY` | Path to security binary | `security` |

### 1Password (`1password`)

Uses 1Password via the `op` CLI. Items use flat naming (`<agent>/<key>`) with a single `value` field, stored in a configurable vault.

| Variable | Description | Default |
| --- | --- | --- |
| `SECRETS_1PASSWORD_VAULT` | 1Password vault name | `Agents` |
| `OP` | Path to op binary | `op` |

<br />

## Testing

```bash
git clone https://github.com/KnickKnackLabs/secrets.git
cd secrets && mise trust && mise install
mise run test
```

**56 tests** across 4 suites, using [BATS](https://github.com/bats-core/bats-core).

External tools (`security`, `op`, `gpg`) are mocked via dependency injection — the libraries accept `$SECURITY`, `$OP`, and `$GPG` environment variables pointing to mock binaries. Tests run against file-backed simulations of each backend, with full isolation per test case. No real keychain, 1Password, or GPG interaction.

## Library architecture

The code is organized as sourced bash libraries, not monolithic task scripts:

```
secrets/
├── lib/
│   ├── keychain.sh       # macOS Keychain provider (keychain_get, keychain_set, keychain_list)
│   └── 1password.sh      # 1Password provider (op_get, op_set, op_list)
├── .mise/tasks/
│   ├── get               # Provider-transparent get (dispatches via SECRETS_PROVIDER)
│   ├── set               # Provider-transparent set
│   ├── list              # List stored keys (dynamic discovery)
│   ├── export            # Export all secrets as GPG-encrypted JSON
│   ├── import            # Import secrets from GPG-encrypted JSON
│   ├── migrate           # Migrate 1Password items from structured to flat naming
│   ├── keychain/         # Direct keychain access
│   └── 1password/        # Direct 1Password access
└── test/
    ├── helpers.bash       # Mock binaries (security, op, gpg) + test isolation
    ├── keychain.bats      # Keychain provider tests
    ├── 1password.bats     # 1Password provider tests
    ├── provider.bats      # Provider dispatch integration tests
    └── export-import.bats # Export/import roundtrip tests
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
