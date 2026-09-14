#!/usr/bin/env python3
"""Validate a flat JSON secret bundle before any provider mutation."""

import json
import sys


class Error(Exception):
    """Safe document diagnostic, never includes a value."""


def dictionary(value):
    if not isinstance(value, dict) or any(
        not isinstance(key, str) or not key
        or any(ord(char) < 32 or ord(char) == 127 for char in key)
        or not isinstance(item, str)
        for key, item in value.items()
    ):
        raise Error("Expected an object of named string values, without control characters in names.")
    try:
        for key, item in value.items():
            key.encode("utf-8")
            item.encode("utf-8")
    except UnicodeError:
        raise Error("Names and values must be valid UTF-8 strings.") from None
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Error("Duplicate JSON key.")
        result[key] = value
    return result


def parse_json(data):
    try:
        return dictionary(json.loads(data, object_pairs_hook=unique_object))
    except (ValueError, UnicodeError):
        raise Error("Invalid JSON secret document.") from None


if __name__ == "__main__":
    try:
        print(json.dumps(parse_json(sys.stdin.buffer.read())))
    except Error as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
