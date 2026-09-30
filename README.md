<div align="center">

<pre>
  ╔════════════════════════════════╗
  ║  secrets get zeke/github-pat  ║
  ╚════════════════════════════════╝
   keychain │ 1password │ sops │ env
</pre>

# secrets

**Provider-transparent, name-agnostic secret management for agents.**

One interface, multiple backends. Store and retrieve agent secrets
through a name-based interface, with explicit provider configuration.

![lang: bash + python](https://img.shields.io/badge/lang-bash%20%2B%20python-4EAA25?style=flat)
[![tests: 137 cases](https://img.shields.io/badge/tests-137%20cases-blue?style=flat)](test/)
![providers: 4 backends](https://img.shields.io/badge/providers-4%20backends-blue?style=flat)
![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat)

</div>

<br />

## Quick start

```bash
# Install
shiv install secrets

# Store a secret from a private input file (using macOS Keychain)
export SECRETS_PROVIDER=keychain
secrets set zeke/github-pat < /path/to/private/token

# Retrieve it
secrets get zeke/github-pat

# Generate a TOTP code from a stored otpauth URI or base32 seed
secrets totp zeke/github-totp

# List what's stored
secrets list --prefix zeke

# Copy values between configured providers (plaintext through the pipe)
secrets export --provider keychain --prefix zeke/ | secrets import --provider 1password
```

## How it works

Every secret is addressed by a single **key** (e.g., `zeke/github-pat`). There is no name registry or agent allowlist. Provider-specific constraints still apply. The `SECRETS_PROVIDER` environment variable (or `--provider` flag) determines which backend handles the request.

```
secrets get <key>
  └─ --provider / SECRETS_PROVIDER
       ├─ keychain   → macOS security
       ├─ 1password  → op
       ├─ sops       → local encrypted YAML + local age identity
       └─ env        → caller's environment (read-only)
```

The provider is just a storage backend. The interface is always the same: `secrets get <key>` and `secrets set <key>`. Configure the selected provider separately; switching providers does not copy data. The env provider is read-only.

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
| `-p, --provider` | Provider: keychain, 1password, or sops (overrides SECRETS_PROVIDER)                                                 | —       |


#### secrets get

Retrieve a secret

```
secrets get <key> [-p <provider>]
```

| Flag             | Description                                                              | Default |
| ---------------- | ------------------------------------------------------------------------ | ------- |
| `-p, --provider` | Provider: keychain, 1password, sops, or env (overrides SECRETS_PROVIDER) | —       |


#### secrets import

Import secrets from a JSON bundle (stdin)

```
secrets import [-p <provider>]
```

| Flag             | Description                                                         | Default |
| ---------------- | ------------------------------------------------------------------- | ------- |
| `-p, --provider` | Provider: keychain, 1password, or sops (overrides SECRETS_PROVIDER) | —       |


#### secrets list

List stored secrets

```
secrets list [--prefix <prefix>] [-p <provider>]
```

| Flag             | Description                                                                                                         | Default |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- | ------- |
| `--prefix`       | Filter keys by prefix (e.g., baby-joel). Uses startswith matching — include trailing / for exact prefix boundaries. | —       |
| `-p, --provider` | Provider: keychain, 1password, or sops (overrides SECRETS_PROVIDER)                                                 | —       |


#### secrets remove

Remove a secret

```
secrets remove <key> [-p <provider>]
```

| Flag             | Description                                                         | Default |
| ---------------- | ------------------------------------------------------------------- | ------- |
| `-p, --provider` | Provider: keychain, 1password, or sops (overrides SECRETS_PROVIDER) | —       |


#### secrets rename

Rename a secret

```
secrets rename <old-key> <new-key> [-p <provider>]
```

| Flag             | Description                                                         | Default |
| ---------------- | ------------------------------------------------------------------- | ------- |
| `-p, --provider` | Provider: keychain, 1password, or sops (overrides SECRETS_PROVIDER) | —       |


#### secrets set

Store a secret

```
secrets set <key> [-v <value>] [-p <provider>]
```

| Flag             | Description                                                            | Default |
| ---------------- | ---------------------------------------------------------------------- | ------- |
| `-v, --value`    | Value to store (prefer stdin to avoid shell history/process arguments) | —       |
| `-p, --provider` | Provider: keychain, 1password, or sops (overrides SECRETS_PROVIDER)    | —       |


#### secrets totp

Generate a TOTP code from a stored secret

```
secrets totp <key> [-p <provider>] [--at <epoch>] [--validate]
```

| Flag             | Description                                                              | Default |
| ---------------- | ------------------------------------------------------------------------ | ------- |
| `-p, --provider` | Provider: keychain, 1password, sops, or env (overrides SECRETS_PROVIDER) | —       |
| `--at`           | Unix timestamp to evaluate (for tests/debugging)                         | —       |
| `--validate`     | Validate the stored TOTP secret without printing a code                  | —       |


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

<br />

## Providers

### macOS Keychain (`keychain`)

Uses the macOS Keychain via the `security` CLI. Values are base64-encoded to handle multi-line secrets (like GPG keys) without corruption.

| Variable                 | Description                  | Default    |
| ------------------------ | ---------------------------- | ---------- |
| `SECRETS_SERVICE_PREFIX` | Keychain service name prefix | `secrets/` |
| `SECURITY`               | Path to security binary      | `security` |

### 1Password (`1password`)

Uses 1Password via the `op` CLI. Items use flat naming (`<agent>/<key>`) with a single concealed `value` field in a Secure Note. Writes use JSON on stdin rather than putting values in op arguments; failed or ambiguous lookups stop instead of creating another item.

| Variable                  | Description          | Default  |
| ------------------------- | -------------------- | -------- |
| `SECRETS_1PASSWORD_VAULT` | 1Password vault name | `Agents` |
| `OP`                      | Path to op binary    | `op`     |

### Local SOPS file (`sops`)

Stores a flat dictionary of UTF-8 string values in one encrypted YAML file. SOPS uses native age support; the separate age CLI is not a runtime dependency. Names remain visible. Slashes in names are literal, not nested paths; the name sops is reserved for metadata.

| Variable                    | Description                                   | Default    |
| --------------------------- | --------------------------------------------- | ---------- |
| `SECRETS_SOPS_FILE`         | Absolute path to the encrypted vault          | `required` |
| `SECRETS_SOPS_AGE_KEY_FILE` | Absolute path to one native age identity file | `required` |
| `SECRETS_SOPS_RECIPIENT`    | One native age public recipient               | `required` |
| `SECRETS_SOPS_BINARY`       | Path to sops binary                           | `sops`     |

### Environment (read-only) (`env`)

Supports get and totp. Names become uppercase environment variables with non-alphanumeric characters replaced by underscores: agent/api-token becomes AGENT_API_TOKEN. Empty or unset variables fail; transformed names cannot start with a digit.

| Variable            | Description                                | Default    |
| ------------------- | ------------------------------------------ | ---------- |
| `<transformed key>` | Value supplied by the caller's environment | `required` |

<br />

## Using a local SOPS vault

Provision a native age identity and its public recipient separately. Keep the identity outside the vault: a key stored only inside its own ciphertext cannot unlock it. Secrets does not generate, install, recover, or rotate keys.

```bash
export SECRETS_PROVIDER=sops
export SECRETS_SOPS_FILE="$HOME/.local/share/my-agent/secrets.enc.yaml"
export SECRETS_SOPS_AGE_KEY_FILE="$HOME/.config/my-agent/age-identity.txt"
export SECRETS_SOPS_RECIPIENT="age1..." # replace with the matching public recipient

# With private directories and the identity already in place:
secrets set agent/api-token < /path/to/private/token
secrets list --prefix agent/
secrets get agent/api-token # writes the exact plaintext value to stdout
```

Vault and identity must be owner-only, singly linked regular files (for example mode 0600), not terminal symlinks. Parent directories must already exist; the vault parent must belong to you and not be writable by others. First set or import creates the vault. A stable private sidecar lock coordinates readers and writers, and a busy vault fails immediately.

Writes decrypt in memory, apply one operation, encrypt and verify the complete dictionary, then atomically publish ciphertext on the same filesystem. Import merges a validated JSON string dictionary in one vault update. Values preserve Unicode, embedded NUL, and trailing newlines; empty values are supported by SOPS but rejected by the existing Keychain and 1Password providers. Names must be nonempty UTF-8 strings without control characters.

This provider writes its own flat, single-recipient document format. It does not preserve arbitrary SOPS metadata, comments, or multiple recipients. It ignores ambient SOPS configuration and key stores; the selected existing vault is trusted input to SOPS, not a network-sandboxed document. File checks and locks do not isolate Secrets from a malicious process running as the same OS user.

Local reads do not sync with storage. Back up and restore the encrypted file explicitly with Blobs or another transport, keeping the bootstrap identity and recovery copy independent.

## Values and disclosure

Use stdin for real values. The legacy --value option exposes its value in process arguments and may leave it in shell history. get and unencrypted export deliberately emit plaintext; direct them only to an approved consumer or protected file. Prefer a pipe over shell command substitution when trailing newlines matter.

SOPS and 1Password writes keep values out of subprocess arguments and suppress raw provider diagnostics. The macOS security CLI still receives a base64-encoded value in its -w argument: base64 is encoding, not secrecy. These interfaces do not protect secrets from the owning account's memory, terminal capture, or compromised consumers.

Imports to Keychain and 1Password validate the whole JSON bundle first, but write entries separately. A later failure returns nonzero while earlier successful writes remain. Legacy rename is likewise a copy followed by delete, not a transaction.

## Testing

```bash
git clone https://github.com/KnickKnackLabs/secrets.git
cd secrets && mise trust && mise install
mise run test
```

**137 tests** across 11 suites, using [BATS](https://github.com/bats-core/bats-core).

External tools (`security`, `op`) are mocked via dependency injection. The libraries accept `$SECURITY` and `$OP` environment variables pointing to absolute mock binaries, including through nested Mise tasks. SOPS tests exercise the declared real binary with public fake age fixtures, isolated configuration, and temporary vaults. BATS cases also run Python tests for local file/locking/failure invariants and provider-assigned 1Password field IDs. The default suite does not use real Keychain or 1Password accounts; this dependency isolation is not an OS sandbox. TOTP generation uses Python's standard library.

## Library architecture

Task entry points dispatch to provider-owned helpers. Exact-value JSON validation is shared by import and the local SOPS provider:

```
secrets/
├── lib/
│   ├── providers/
│   │   ├── env.sh          # Read-only environment provider
│   │   ├── keychain.sh     # macOS Keychain provider
│   │   ├── onepassword/
│   │   │   ├── provider.sh # Task-facing read/list/delete/write functions
│   │   │   ├── write.py    # Lookup, validation, JSON-stdin write and verification
│   │   │   └── migrate.py  # Legacy field-to-flat migration using the same writer
│   │   └── sops/
│   │       ├── __main__.py # Command dispatch and deliberate plaintext output
│   │       ├── vault.py    # Private files, locks, atomic ciphertext publication
│   │       └── encryption.py # Validated documents and authenticated SOPS operations
│   ├── document.py         # Shared flat JSON string-dictionary validation
│   ├── values.sh           # CLI stdin/value selection
│   └── totp.py             # TOTP parsing/generation helper
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
│   └── 1password/        # Direct 1Password access
└── test/
    ├── helpers.bash       # Mock binaries (security, op) + test isolation
    ├── keychain.bats      # Keychain provider tests
    ├── 1password.bats     # 1Password provider tests
    ├── crud.bats          # End-to-end CRUD integration tests
    ├── delete-rename.bats # Delete and rename operation tests
    ├── provider.bats      # Provider dispatch integration tests
    ├── export-import.bats # Export/import roundtrip tests
    ├── migrate.bats       # Mock-only 1Password migration tests
    ├── values.bats        # Exact values and safe 1Password write boundary
    ├── onepassword_write.py # Provider field identities and response verification
    ├── sops.bats          # Real SOPS with public fake keys
    ├── sops_invariants.py # Local file, lock, and failure-boundary tests
    └── totp.bats          # TOTP parsing/generation tests
```

Provider implementations live under lib/providers/. Single-file providers stay simple; SOPS and 1Password have directories for their distinct responsibilities. Shared value and document helpers stay outside. Read SOPS from providers/sops/__main__.py into vault.py, then encryption.py. Commands select the operation; the vault owns storage; encryption owns the authenticated document format and subprocess. Lower layers never call back into command handling. Tasks source Bash providers and run Python providers as modules with lib on their explicit Python path. Values travel over stdin. Tests cover these boundaries and the actual Mise-dispatched command path.

<br />

<div align="center">

---

<sub>
One interface. Any backend. Any key.<br />
Your secrets, wherever they need to be.<br />
<br />
This README was generated from <a href="https://github.com/KnickKnackLabs/readme">README.tsx</a>.
</sub></div>
