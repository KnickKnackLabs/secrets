/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync, existsSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock, LineBreak, HR,
  Bold, Italic, Code, Link,
  Badge, Badges, Center, Section,
  Table, TableHead, TableRow, Cell,
  List, Item,
  Raw, HtmlLink, Sub, HtmlTable, HtmlTr, HtmlTd,
} from "readme/src/components";

// ── Dynamic data ─────────────────────────────────────────────

const REPO_DIR = resolve(import.meta.dirname);
const TASK_DIR = join(REPO_DIR, ".mise/tasks");
const LIB_DIR = join(REPO_DIR, "lib");
const TEST_DIR = join(REPO_DIR, "test");

// ── Parse tasks ──────────────────────────────────────────────

interface Flag {
  name: string;
  shortFlag?: string;
  valueName?: string;
  help: string;
  required?: boolean;
  default?: string;
  isBoolean: boolean;
}

interface Arg {
  name: string;
  help: string;
  optional: boolean;
}

interface Command {
  name: string;
  description: string;
  flags: Flag[];
  args: Arg[];
  hidden: boolean;
}

function parseTask(filepath: string, name: string): Command {
  const src = readFileSync(filepath, "utf-8");
  const lines = src.split("\n");

  const desc =
    lines
      .find((l) => l.startsWith("#MISE description="))
      ?.match(/#MISE description="(.+)"/)?.[1] ?? "";

  const hidden = lines.some((l) => l.includes("#MISE hide=true"));

  const flags: Flag[] = [];
  const args: Arg[] = [];

  for (const line of lines) {
    const flagMatch = line.match(
      /#USAGE flag "(-[\w-]+ )?--(\w[\w-]*)(?:\s+<([\w-]+)>)?" help="([^"]+)"(.*)/
    );
    if (flagMatch) {
      const shortFlag = flagMatch[1]?.trim();
      const flagName = flagMatch[2].replace(/_/g, "-");
      const valueName = flagMatch[3];
      const help = flagMatch[4];
      const rest = flagMatch[5] || "";
      const required = rest.includes("required=#true");
      const defMatch = rest.match(/default="([^"]+)"/);
      flags.push({
        name: `--${flagName}`,
        shortFlag,
        valueName,
        help,
        required: required || undefined,
        default: defMatch?.[1],
        isBoolean: !valueName,
      });
    }

    // Required arg: <name>
    const reqArgMatch = line.match(/#USAGE arg "<(.+?)>" help="([^"]+)"/);
    if (reqArgMatch) {
      args.push({ name: reqArgMatch[1], help: reqArgMatch[2], optional: false });
      continue;
    }

    // Optional arg: [name]
    const optArgMatch = line.match(/#USAGE arg "\[(.+?)\]" help="([^"]+)"/);
    if (optArgMatch) {
      args.push({ name: optArgMatch[1], help: optArgMatch[2], optional: true });
    }
  }

  return { name, description: desc, flags, args, hidden };
}

// Walk task directories (supports nested like keychain/get → keychain:get)
function walkTasks(dir: string, prefix = ""): Command[] {
  const results: Command[] = [];
  if (!existsSync(dir)) return results;

  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || entry.name.startsWith("_")) continue;
    const fullPath = join(dir, entry.name);
    const taskName = prefix ? `${prefix}:${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      results.push(...walkTasks(fullPath, taskName));
    } else {
      results.push(parseTask(fullPath, taskName));
    }
  }
  return results;
}

const commands = walkTasks(TASK_DIR)
  .filter((c) => !c.hidden && c.name !== "test" && c.name !== "migrate" && !c.name.startsWith("test:"))
  .sort((a, b) => a.name.localeCompare(b.name));

// Count tests
const testFiles = readdirSync(TEST_DIR).filter((f) => f.endsWith(".bats"));
const testSrc = testFiles
  .map((f) => readFileSync(join(TEST_DIR, f), "utf-8"))
  .join("\n");
const testCount = [...testSrc.matchAll(/@test "/g)].length;

// ── Providers ────────────────────────────────────────────────

const providers = [
  {
    name: "keychain",
    label: "macOS Keychain",
    tool: "security",
    description: "Uses the macOS Keychain via the `security` CLI. Values are base64-encoded to handle multi-line secrets (like GPG keys) without corruption.",
    env: [
      { var: "SECRETS_SERVICE_PREFIX", desc: "Keychain service name prefix", default: "secrets/" },
      { var: "SECURITY", desc: "Path to security binary", default: "security" },
    ],
  },
  {
    name: "1password",
    label: "1Password",
    tool: "op",
    description: "Uses 1Password via the `op` CLI. Items use flat naming (`<agent>/<key>`) with a single concealed `value` field in a Secure Note. Writes use JSON on stdin rather than putting values in op arguments; failed or ambiguous lookups stop instead of creating another item.",
    env: [
      { var: "SECRETS_1PASSWORD_VAULT", desc: "1Password vault name", default: "Agents" },
      { var: "OP", desc: "Path to op binary", default: "op" },
    ],
  },
  {
    name: "sops",
    label: "Local SOPS file",
    tool: "sops",
    description: "Stores a flat dictionary of UTF-8 string values in one encrypted YAML file. SOPS uses native age support; the separate age CLI is not a runtime dependency. Names remain visible. Slashes in names are literal, not nested paths; the name sops is reserved for metadata.",
    env: [
      { var: "SECRETS_SOPS_FILE", desc: "Absolute path to the encrypted vault", default: "required" },
      { var: "SECRETS_SOPS_AGE_KEY_FILE", desc: "Absolute path to one native age identity file", default: "required" },
      { var: "SECRETS_SOPS_RECIPIENT", desc: "One native age public recipient", default: "required" },
      { var: "SECRETS_SOPS_BINARY", desc: "Path to sops binary", default: "sops" },
    ],
  },
  {
    name: "env",
    label: "Environment (read-only)",
    tool: "bash",
    description: "Supports get and totp. Names become uppercase environment variables with non-alphanumeric characters replaced by underscores: agent/api-token becomes AGENT_API_TOKEN. Empty or unset variables fail; transformed names cannot start with a digit.",
    env: [
      { var: "<transformed key>", desc: "Value supplied by the caller's environment", default: "required" },
    ],
  },
];

// ── Architecture diagram ─────────────────────────────────────

const archDiagram = [
  "secrets get <key>",
  "  └─ --provider / SECRETS_PROVIDER",
  "       ├─ keychain   → macOS security",
  "       ├─ 1password  → op",
  "       ├─ sops       → local encrypted YAML + local age identity",
  "       └─ env        → caller's environment (read-only)",
].join("\n");

// ── Helpers ──────────────────────────────────────────────────

function cmdUsage(cmd: Command): string {
  const parts = [`secrets ${cmd.name}`];
  for (const a of cmd.args) {
    parts.push(a.optional ? `[${a.name}]` : `<${a.name}>`);
  }
  for (const f of cmd.flags) {
    const flagStr = f.shortFlag ? `${f.shortFlag}` : f.name;
    const val = f.isBoolean ? "" : ` <${f.valueName ?? f.name.replace("--", "")}>`;
    parts.push(f.required ? `${flagStr}${val}` : `[${flagStr}${val}]`);
  }
  return parts.join(" ");
}

// Group commands: top-level vs provider-specific
const topLevel = commands.filter((c) => !c.name.includes(":"));
const providerCmds = commands.filter((c) => c.name.includes(":"));

// ── README ───────────────────────────────────────────────────

const readme = (
  <>
    <Center>
      <Raw>{`<pre>\n` +
`  ╔════════════════════════════════╗\n` +
`  ║  secrets get zeke/github-pat  ║\n` +
`  ╚════════════════════════════════╝\n` +
`   keychain │ 1password │ sops │ env\n` +
`</pre>\n\n`}</Raw>

      <Heading level={1}>secrets</Heading>

      <Paragraph>
        <Bold>Provider-transparent, name-agnostic secret management for agents.</Bold>
      </Paragraph>

      <Paragraph>
        {"One interface, multiple backends. Store and retrieve agent secrets"}
        {"\n"}
        {"through a name-based interface, with explicit provider configuration."}
      </Paragraph>

      <Badges>
        <Badge label="lang" value="bash + python" color="4EAA25" />
        <Badge label="tests" value={`${testCount} cases`} color="blue" href="test/" />
        <Badge label="providers" value={`${providers.length} backends`} color="blue" />
        <Badge label="License" value="MIT" color="blue" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="Quick start">
      <CodeBlock lang="bash">{`# Install
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
secrets export --provider keychain --prefix zeke/ | secrets import --provider 1password`}</CodeBlock>
    </Section>

    <Section title="How it works">
      <Paragraph>
        {"Every secret is addressed by a single "}
        <Bold>key</Bold>
        {" (e.g., "}
        <Code>zeke/github-pat</Code>
        {"). There is no name registry or agent allowlist. Provider-specific constraints still apply. The "}
        <Code>SECRETS_PROVIDER</Code>
        {" environment variable (or "}
        <Code>--provider</Code>
        {" flag) determines which backend handles the request."}
      </Paragraph>

      <CodeBlock>{archDiagram}</CodeBlock>

      <Paragraph>
        {"The provider is just a storage backend. The interface is always the same: "}
        <Code>{"secrets get <key>"}</Code>
        {" and "}
        <Code>{"secrets set <key>"}</Code>
        {". Configure the selected provider separately; switching providers does not copy data. The env provider is read-only."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Section title="Commands">
      <Heading level={3}>Core</Heading>

      <Paragraph>
        {"The provider-transparent interface — these dispatch to whichever backend "}
        <Code>SECRETS_PROVIDER</Code>
        {" points to:"}
      </Paragraph>

      {topLevel.map((cmd) => (
        <>
          <Raw>{`\n`}</Raw>
          <Heading level={4}>{`secrets ${cmd.name}`}</Heading>
          <Paragraph>{cmd.description}</Paragraph>
          <CodeBlock>{cmdUsage(cmd)}</CodeBlock>
          {cmd.flags.length > 0 ? (
            <Table>
              <TableHead>
                <Cell>Flag</Cell>
                <Cell>Description</Cell>
                <Cell>Default</Cell>
              </TableHead>
              {cmd.flags.map((f) => (
                <TableRow>
                  <Cell>
                    <Code>
                      {f.shortFlag ? `${f.shortFlag}, ${f.name}` : f.name}
                    </Code>
                  </Cell>
                  <Cell>
                    {f.help}
                    {f.required ? " **(required)**" : ""}
                  </Cell>
                  <Cell>{f.default ? <Code>{f.default}</Code> : "—"}</Cell>
                </TableRow>
              ))}
            </Table>
          ) : (
            ""
          )}
        </>
      ))}

      <Raw>{`\n`}</Raw>
      <Heading level={3}>Provider-specific</Heading>

      <Paragraph>
        {"Direct access to a specific backend — no "}
        <Code>SECRETS_PROVIDER</Code>
        {" needed:"}
      </Paragraph>

      {providerCmds.map((cmd) => (
        <>
          <Raw>{`\n`}</Raw>
          <Heading level={4}>{`secrets ${cmd.name}`}</Heading>
          <Paragraph>{cmd.description}</Paragraph>
          <CodeBlock>{cmdUsage(cmd)}</CodeBlock>
        </>
      ))}
    </Section>

    <LineBreak />

    <Section title="Providers">
      {providers.map((p) => (
        <>
          <Heading level={3}>{`${p.label} (\`${p.name}\`)`}</Heading>

          <Paragraph>{p.description}</Paragraph>

          <Table>
            <TableHead>
              <Cell>Variable</Cell>
              <Cell>Description</Cell>
              <Cell>Default</Cell>
            </TableHead>
            {p.env.map((e) => (
              <TableRow>
                <Cell>
                  <Code>{e.var}</Code>
                </Cell>
                <Cell>{e.desc}</Cell>
                <Cell>
                  <Code>{e.default}</Code>
                </Cell>
              </TableRow>
            ))}
          </Table>
        </>
      ))}
    </Section>

    <LineBreak />

    <Section title="Using a local SOPS vault">
      <Paragraph>
        {"Provision a native age identity and its public recipient separately. Keep the identity outside the vault: a key stored only inside its own ciphertext cannot unlock it. Secrets does not generate, install, recover, or rotate keys."}
      </Paragraph>
      <CodeBlock lang="bash">{`export SECRETS_PROVIDER=sops
export SECRETS_SOPS_FILE="$HOME/.local/share/my-agent/secrets.enc.yaml"
export SECRETS_SOPS_AGE_KEY_FILE="$HOME/.config/my-agent/age-identity.txt"
export SECRETS_SOPS_RECIPIENT="age1..." # replace with the matching public recipient

# With private directories and the identity already in place:
secrets set agent/api-token < /path/to/private/token
secrets list --prefix agent/
secrets get agent/api-token # writes the exact plaintext value to stdout`}</CodeBlock>
      <Paragraph>
        {"Vault and identity must be owner-only, singly linked regular files (for example mode 0600), not terminal symlinks. Parent directories must already exist; the vault parent must belong to you and not be writable by others. First set or import creates the vault. A stable private sidecar lock coordinates readers and writers, and a busy vault fails immediately."}
      </Paragraph>
      <Paragraph>
        {"Writes decrypt in memory, apply one operation, encrypt and verify the complete dictionary, then atomically publish ciphertext on the same filesystem. Import merges a validated JSON string dictionary in one vault update. Values preserve Unicode, embedded NUL, and trailing newlines; empty values are supported by SOPS but rejected by the existing Keychain and 1Password providers. Names must be nonempty UTF-8 strings without control characters."}
      </Paragraph>
      <Paragraph>
        {"This provider writes its own flat, single-recipient document format. It does not preserve arbitrary SOPS metadata, comments, or multiple recipients. It ignores ambient SOPS configuration and key stores; the selected existing vault is trusted input to SOPS, not a network-sandboxed document. File checks and locks do not isolate Secrets from a malicious process running as the same OS user."}
      </Paragraph>
      <Paragraph>
        {"Local reads do not sync with storage. Back up and restore the encrypted file explicitly with Blobs or another transport, keeping the bootstrap identity and recovery copy independent."}
      </Paragraph>
    </Section>

    <Section title="Values and disclosure">
      <Paragraph>
        {"Use stdin for real values. The legacy --value option exposes its value in process arguments and may leave it in shell history. get and unencrypted export deliberately emit plaintext; direct them only to an approved consumer or protected file. Prefer a pipe over shell command substitution when trailing newlines matter."}
      </Paragraph>
      <Paragraph>
        {"SOPS and 1Password writes keep values out of subprocess arguments and suppress raw provider diagnostics. The macOS security CLI still receives a base64-encoded value in its -w argument: base64 is encoding, not secrecy. These interfaces do not protect secrets from the owning account's memory, terminal capture, or compromised consumers."}
      </Paragraph>
      <Paragraph>
        {"Imports to Keychain and 1Password validate the whole JSON bundle first, but write entries separately. A later failure returns nonzero while earlier successful writes remain. Legacy rename is likewise a copy followed by delete, not a transaction."}
      </Paragraph>
    </Section>

    <Section title="Testing">
      <CodeBlock lang="bash">{`git clone https://github.com/KnickKnackLabs/secrets.git
cd secrets && mise trust && mise install
mise run test`}</CodeBlock>

      <Paragraph>
        <Bold>{`${testCount} tests`}</Bold>
        {` across ${testFiles.length} suites, using `}
        <Link href="https://github.com/bats-core/bats-core">BATS</Link>
        {"."}
      </Paragraph>

      <Paragraph>
        {"External tools ("}
        <Code>security</Code>
        {", "}
        <Code>op</Code>
        {") are mocked via dependency injection. The libraries accept "}
        <Code>$SECURITY</Code>
        {" and "}
        <Code>$OP</Code>
        {" environment variables pointing to absolute mock binaries, including through nested Mise tasks. SOPS tests exercise the declared real binary with public fake age fixtures, isolated configuration, and temporary vaults. BATS cases also run Python tests for local file/locking/failure invariants and provider-assigned 1Password field IDs. The default suite does not use real Keychain or 1Password accounts; this dependency isolation is not an OS sandbox. TOTP generation uses Python's standard library."}
      </Paragraph>
    </Section>

    <Section title="Library architecture">
      <Paragraph>
        {"Task entry points dispatch to provider-owned helpers. Exact-value JSON validation is shared by import and the local SOPS provider:"}
      </Paragraph>

      <CodeBlock>{`secrets/
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
    └── totp.bats          # TOTP parsing/generation tests`}</CodeBlock>

      <Paragraph>
        {"Provider implementations live under lib/providers/. Single-file providers stay simple; SOPS and 1Password have directories for their distinct responsibilities. Shared value and document helpers stay outside. Read SOPS from providers/sops/__main__.py into vault.py, then encryption.py. Commands select the operation; the vault owns storage; encryption owns the authenticated document format and subprocess. Lower layers never call back into command handling. Tasks source Bash providers and run Python providers as modules with lib on their explicit Python path. Values travel over stdin. Tests cover these boundaries and the actual Mise-dispatched command path."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Center>
      <HR />

      <Sub>
        {"One interface. Any backend. Any key."}
        <Raw>{"<br />"}</Raw>{"\n"}
        {"Your secrets, wherever they need to be."}
        <Raw>{"<br />"}</Raw>{"\n"}
        <Raw>{"<br />"}</Raw>{"\n"}
        {"This README was generated from "}
        <HtmlLink href="https://github.com/KnickKnackLabs/readme">README.tsx</HtmlLink>
        {"."}
      </Sub>
    </Center>
  </>
);

console.log(readme);
