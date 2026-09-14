#!/usr/bin/env python3
"""Copy frozen legacy fields to flat items without exposing values in argv."""

import sys

from .write import Error, list_items, request, write

# This mapping is historical migration policy, not a secret-name registry.
LEGACY_KEYS = (
    ("github-pat", "GitHub", "PAT"),
    ("github-password", "GitHub", "password"),
    ("gpg-private-key", "GPG", "Private Key"),
    ("gpg-public-key", "GPG", "Public Key"),
    ("gpg-key-id", "GPG", "Key ID"),
    ("gpg-fingerprint", "GPG", "Fingerprint"),
    ("email-password", "Email", "password"),
    ("matrix-password", "Matrix", "password"),
    ("passphrase", "Identity", "passphrase"),
    ("b2-key-id", "B2", "Key ID"),
    ("b2-application-key", "B2", "Application Key"),
    ("b2-bucket", "B2", "Bucket"),
    ("b2-endpoint", "B2", "Endpoint"),
)


def legacy_value(items, title, label):
    """Read an unambiguous legacy field; absent and empty fields are skipped."""
    matches = [item for item in items if item.get("title") == title]
    if len(matches) > 1:
        raise Error("Duplicate legacy titles; refusing an ambiguous migration.")
    if not matches:
        return None
    item_id = matches[0].get("id")
    if not isinstance(item_id, str) or not item_id:
        raise Error("Missing legacy item identity.")
    item = request("get", item_id)
    if (
        not isinstance(item, dict)
        or item.get("id") != item_id
        or item.get("title") != title
        or not isinstance(item.get("fields"), list)
    ):
        raise Error("Unexpected legacy item response.")
    fields = [
        field for field in item["fields"] if isinstance(field, dict)
        and (field.get("id") == label or field.get("label") == label)
    ]
    if len(fields) > 1:
        raise Error("Ambiguous legacy field.")
    if not fields:
        return None
    value = fields[0].get("value")
    if not isinstance(value, str):
        raise Error("Legacy field is not a string.")
    return value or None


def migrate(agent, dry_run):
    items = list_items()
    migrated = skipped = 0
    for key, suffix, label in LEGACY_KEYS:
        old_name, new_name = f"{agent} - {suffix}", f"{agent}/{key}"
        value = legacy_value(items, old_name, label)
        if value is None:
            skipped += 1
            continue
        if any(candidate.get("title") == new_name for candidate in items):
            print(f"SKIP {key}: destination already exists")
            skipped += 1
            continue
        if dry_run:
            print(f"[dry-run] Would migrate: {old_name}/{label} → {new_name}/value")
        elif not write(new_name, value, create_only=True):
            skipped += 1
            continue
        else:
            print(f"{key}: {old_name}/{label} → {new_name}/value")
        migrated += 1
    print(f"Migration complete: {migrated} migrated, {skipped} skipped, 0 errors")
    if migrated and not dry_run:
        print("Old items are preserved; verify before deleting them manually.")


if __name__ == "__main__":
    try:
        migrate(sys.argv[1], sys.argv[2:] == ["--dry-run"])
    except (Error, UnicodeError, KeyError, TypeError, AttributeError):
        print("ERROR: Migration stopped; earlier copies may remain. No source items deleted.",
              file=sys.stderr)
        sys.exit(1)
