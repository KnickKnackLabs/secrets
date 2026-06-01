#!/usr/bin/env python3
"""Generate TOTP codes from raw base32 secrets or otpauth:// URIs."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import re
import struct
import sys
import time
from urllib.parse import parse_qs, urlparse

ALGORITHMS = {
    "SHA1": hashlib.sha1,
    "SHA256": hashlib.sha256,
    "SHA512": hashlib.sha512,
}


def fail(key: str) -> None:
    print(f"ERROR: {key} is not a valid TOTP secret or otpauth URI", file=sys.stderr)
    raise SystemExit(1)


def parse_secret(value: str, key: str) -> tuple[bytes, int, int, str]:
    value = value.strip()
    if not value:
        fail(key)

    digits = 6
    period = 30
    algorithm = "SHA1"

    if value.startswith("otpauth://"):
        uri = urlparse(value)
        if uri.scheme != "otpauth" or uri.netloc != "totp":
            fail(key)

        params = parse_qs(uri.query)
        secret = params.get("secret", [""])[0]
        algorithm = params.get("algorithm", [algorithm])[0].upper()

        if "digits" in params:
            try:
                digits = int(params["digits"][0])
            except ValueError:
                fail(key)

        if "period" in params:
            try:
                period = int(params["period"][0])
            except ValueError:
                fail(key)
    else:
        secret = value

    if algorithm not in ALGORITHMS or digits < 6 or digits > 10 or period <= 0:
        fail(key)

    normalized = re.sub(r"[\s-]", "", secret).upper()
    if not re.fullmatch(r"[A-Z2-7]+=*", normalized):
        fail(key)

    normalized += "=" * ((8 - len(normalized) % 8) % 8)

    try:
        key_bytes = base64.b32decode(normalized, casefold=True)
    except Exception:
        fail(key)

    if not key_bytes:
        fail(key)

    return key_bytes, digits, period, algorithm


def totp_code(key_bytes: bytes, digits: int, period: int, algorithm: str, timestamp: int) -> str:
    counter = timestamp // period
    message = struct.pack(">Q", counter)
    digest = hmac.new(key_bytes, message, ALGORITHMS[algorithm]).digest()
    offset = digest[-1] & 0x0F
    truncated = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return str(truncated % (10**digits)).zfill(digits)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a TOTP code without printing the secret")
    parser.add_argument("key", help="Secret key name used only for safe error messages")
    parser.add_argument("--at", type=int, default=None, help="Unix timestamp to evaluate")
    parser.add_argument("--validate", action="store_true", help="Validate without printing a code")
    args = parser.parse_args()

    key_bytes, digits, period, algorithm = parse_secret(sys.stdin.read(), args.key)

    if args.validate:
        print("OK")
        return 0

    timestamp = int(time.time()) if args.at is None else args.at
    if timestamp < 0:
        fail(args.key)

    print(totp_code(key_bytes, digits, period, algorithm, timestamp))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
