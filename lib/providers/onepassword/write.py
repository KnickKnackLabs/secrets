#!/usr/bin/env python3
"""Write one 1Password Secure Note via JSON stdin, never secret arguments."""

import json
import os
import subprocess
import sys


class Error(Exception):
    """Diagnostics must not contain provider output or values."""


def request(*args, payload=None):
    try:
        result = subprocess.run(
            [os.environ.get("OP", "op"), "item", *args,
             "--vault", os.environ.get("SECRETS_1PASSWORD_VAULT", "Agents"),
             "--format", "json"],
            input=b"" if payload is None else json.dumps(payload).encode("utf-8"),
            capture_output=True, timeout=20,
        )
        if result.returncode:
            raise Error("1Password request failed; no write fallback attempted.")
        return json.loads(result.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        raise Error("1Password request or response could not be verified.") from None


def list_items():
    items = request("list")
    if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
        raise Error("Invalid 1Password item inventory.")
    return items


def find_destination(key):
    matches = [item for item in list_items() if item.get("title") == key]
    if len(matches) > 1:
        raise Error("Duplicate 1Password titles; refusing an ambiguous write.")
    return matches[0] if matches else None


def load_note(match, key):
    item_id = match.get("id")
    if not isinstance(item_id, str) or not item_id:
        raise Error("Missing 1Password item identity.")
    item = request("get", item_id)
    if (
        not isinstance(item, dict)
        or item.get("id") != item_id
        or item.get("title") != key
        or item.get("category") != "SECURE_NOTE"
        or not isinstance(item.get("fields"), list)
        or not isinstance(item.get("vault"), dict)
        or not item["vault"].get("id")
        or item["vault"].get("id") != match.get("vault", {}).get("id")
    ):
        raise Error("Existing item is not the expected Secure Note.")
    return item


def value_field(item):
    fields = [
        field for field in item["fields"] if isinstance(field, dict)
        and (field.get("id") == "value" or field.get("label") == "value")
    ]
    if (
        len(fields) != 1
        or fields[0].get("type") != "CONCEALED"
        or fields[0].get("id") != "value"
        or fields[0].get("label") != "value"
    ):
        raise Error("Existing item has an unexpected value field.")
    return fields[0]


def new_note(key, value):
    return {
        "title": key,
        "category": "SECURE_NOTE",
        "fields": [{"id": "value", "label": "value", "type": "CONCEALED", "value": value}],
    }


def verify_write(result, key, value):
    if (
        not isinstance(result, dict)
        or result.get("title") != key
        or not isinstance(result.get("fields"), list)
        or [field.get("value") for field in result["fields"]
            if isinstance(field, dict) and field.get("id") == "value"] != [value]
    ):
        raise Error("Write response could not be verified; check the item before retrying.")


def write(key, value, create_only=False):
    if not value:
        raise Error("Empty value.")
    match = find_destination(key)
    if match is not None:
        if create_only:
            print(f"SKIP: key={key} already exists")
            return False
        item = load_note(match, key)
        value_field(item)["value"] = value
        result = request("edit", match["id"], payload=item)
    else:
        result = request("create", "-", payload=new_note(key, value))
    verify_write(result, key, value)
    print(f"Stored: key={key}")
    return True


if __name__ == "__main__":
    try:
        write(sys.argv[1], sys.stdin.buffer.read().decode("utf-8"),
              create_only=sys.argv[2:] == ["--create-only"])
    except Error as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
    except (UnicodeError, KeyError, TypeError, AttributeError):
        # Provider responses can include secrets even on failure.
        print("ERROR: 1Password write failed; check authentication and item schema.", file=sys.stderr)
        sys.exit(1)
