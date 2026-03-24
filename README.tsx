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
    description: "Uses 1Password via the `op` CLI. Items use flat naming (`<agent>/<key>`) with a single `value` field, stored in a configurable vault.",
    env: [
      { var: "SECRETS_1PASSWORD_VAULT", desc: "1Password vault name", default: "Agents" },
      { var: "OP", desc: "Path to op binary", default: "op" },
    ],
  },
];

// ── Architecture diagram ─────────────────────────────────────

const archDiagram = [
  "                      secrets get <key>",
  "                            │",
  "                   ┌────────┴────────┐",
  "                   │ SECRETS_PROVIDER │",
  "                   └────────┬────────┘",
  "              ┌─────────────┼─────────────┐",
  "              ▼             ▼             ▼",
  "        ┌──────────┐ ┌──────────┐ ┌──────────┐",
  "        │ keychain │ │ 1password│ │  (more)  │",
  "        │ (macOS)  │ │   (op)   │ │  (soon)  │",
  "        └──────────┘ └──────────┘ └──────────┘",
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
`     keychain ✓  │  1password ✓\n` +
`</pre>\n\n`}</Raw>

      <Heading level={1}>secrets</Heading>

      <Paragraph>
        <Bold>Provider-transparent, name-agnostic secret management for agents.</Bold>
      </Paragraph>

      <Paragraph>
        {"One interface, multiple backends. Store and retrieve agent secrets"}
        {"\n"}
        {"without knowing — or caring — where they live. Any key name works."}
      </Paragraph>

      <Badges>
        <Badge label="lang" value="bash" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" href="test/" />
        <Badge label="providers" value={`${providers.length} backends`} color="blue" />
        <Badge label="License" value="MIT" color="blue" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="Quick start">
      <CodeBlock lang="bash">{`# Install
shiv install secrets

# Store a secret (using macOS Keychain)
export SECRETS_PROVIDER=keychain
secrets set zeke/github-pat --value "ghp_abc123..."

# Retrieve it
secrets get zeke/github-pat

# List what's stored
secrets list --prefix zeke

# Transfer secrets between machines
secrets export --prefix zeke | secrets import --provider keychain`}</CodeBlock>
    </Section>

    <Section title="How it works">
      <Paragraph>
        {"Every secret is addressed by a single "}
        <Bold>key</Bold>
        {" (e.g., "}
        <Code>zeke/github-pat</Code>
        {"). Key names are arbitrary — there's no registry or allowlist. The "}
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
        {". Switch providers by changing one env var — no code changes, no data format differences."}
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
        {") are mocked via dependency injection — the libraries accept "}
        <Code>$SECURITY</Code>
        {" and "}
        <Code>$OP</Code>
        {" environment variables pointing to mock binaries. Tests run against file-backed simulations of each backend, with full isolation per test case. No real keychain or 1Password interaction."}
      </Paragraph>
    </Section>

    <Section title="Library architecture">
      <Paragraph>
        {"The code is organized as sourced bash libraries, not monolithic task scripts:"}
      </Paragraph>

      <CodeBlock>{`secrets/
├── lib/
│   ├── keychain.sh       # macOS Keychain provider (keychain_get, keychain_set, keychain_list)
│   └── 1password.sh      # 1Password provider (op_get, op_set, op_list)
├── .mise/tasks/
│   ├── get               # Provider-transparent get (dispatches via SECRETS_PROVIDER)
│   ├── set               # Provider-transparent set
│   ├── remove            # Provider-transparent remove
│   ├── list              # List stored keys (dynamic discovery)
│   ├── export            # Export all secrets as plain JSON
│   ├── import            # Import secrets from a JSON bundle
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
    └── migrate.bats       # 1Password migration tests`}</CodeBlock>

      <Paragraph>
        {"Libraries are sourced by tasks and tests alike — making every function independently testable. The task scripts are thin entry points that parse args, source the right library, and call one function."}
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
