#!/usr/bin/env python3
"""SOPS command entry point: select an operation and report its result."""

import json
import sys

from document import Error
from .encryption import parse_values, validate_values
from .vault import Vault, vault_lock


def apply(operation, args, values):
    """Apply one requested mutation in memory before the vault is saved."""
    if operation == "set":
        key, = args
        try:
            values[key] = sys.stdin.buffer.read().decode("utf-8")
        except UnicodeError:
            raise Error("Secret values must be UTF-8 strings.") from None
        validate_values(values)
        return f"Stored: key={key}"

    if operation == "import":
        incoming = parse_values(sys.stdin.buffer.read())
        values.update(incoming)
        return f"Imported {len(incoming)} secret(s) into provider=sops"

    if operation == "remove":
        key, = args
        if key not in values:
            raise Error("Secret not found.")
        del values[key]
        return f"Deleted: key={key}"

    if operation == "rename":
        old, new = args
        if old not in values:
            raise Error("Secret not found.")
        if new in values:
            raise Error("Destination key already exists.")
        values[new] = values.pop(old)
        validate_values(values)
        return f"Renamed: key={old} → {new}"

    raise Error("Unknown SOPS operation.")


def show(operation, args, values):
    """Only get and export deliberately emit plaintext values."""
    if operation == "get":
        key, = args
        if key not in values:
            raise Error("Secret not found.")
        sys.stdout.buffer.write(values[key].encode("utf-8"))
        return

    if operation in {"list", "export"}:
        prefix, = args
        selected = {key: values[key] for key in sorted(values) if key.startswith(prefix)}
        if operation == "list":
            print("\n".join(f"  ✓ {key}" for key in selected) or "  (no secrets found)")
        else:
            if not selected:
                raise Error("No secrets found.")
            print(json.dumps(selected, ensure_ascii=False))
        return

    raise Error("Unknown SOPS operation.")


def main():
    operation, *args = sys.argv[1:]
    writing = operation in {"set", "import", "remove", "rename"}
    vault = Vault()
    with vault_lock(vault.path, writing):
        values = vault.load(allow_missing=operation in {"set", "import"})
        if writing:
            message = apply(operation, args, values)
            vault.save(values)
            print(message)
        else:
            show(operation, args, values)


if __name__ == "__main__":
    try:
        main()
    except Error as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, TypeError):
        print("ERROR: Local SOPS operation failed; no secret data shown.", file=sys.stderr)
        sys.exit(1)
