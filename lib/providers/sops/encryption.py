"""Authenticate and encrypt flat secret dictionaries through isolated SOPS."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from document import Error, dictionary, parse_json


def validate_values(values):
    dictionary(values)
    if "sops" in values:
        raise Error("The name sops is reserved for document metadata.")
    return values


def parse_values(data):
    return validate_values(parse_json(data))


class EncryptedDocument:
    """Own the document format, native age settings, and SOPS process boundary."""

    def __init__(self, identity, recipient, binary):
        lines = [
            line for line in identity.read_text().splitlines()
            if line and not line.startswith("#")
        ]
        if len(lines) != 1 or not re.fullmatch(r"AGE-SECRET-KEY-1[0-9A-Z]{58}", lines[0]):
            raise Error("Identity must contain one native age secret key, not a plugin identity.")
        if not re.fullmatch(r"age1[0-9a-z]{58}", recipient):
            raise Error("SECRETS_SOPS_RECIPIENT must be one native age recipient.")
        self.identity = identity
        self.recipient = recipient
        self.binary = binary

    def decrypt(self, ciphertext):
        return parse_values(self._run("decrypt", ciphertext))

    def encrypt(self, values):
        plaintext = json.dumps(validate_values(values), ensure_ascii=False).encode("utf-8")
        ciphertext = self._run("encrypt", plaintext)
        if self.decrypt(ciphertext) != values:
            raise Error("Encrypted document failed round-trip verification.")
        return ciphertext

    def _run(self, operation, data):
        # Ignore ambient config, identities, cloud credentials, and key commands.
        # The selected document is still trusted input to SOPS, not a network sandbox.
        with tempfile.TemporaryDirectory(prefix="secrets-sops-") as directory:
            config = Path(directory) / "config.json"
            config.write_text(json.dumps({"creation_rules": [{
                "age": self.recipient,
                "encrypted_regex": ".*",
            }]}))
            environment = {
                "PATH": os.environ.get("PATH", os.defpath),
                "HOME": directory,
                "XDG_CONFIG_HOME": directory,
                "SOPS_AGE_KEY_FILE": str(self.identity),
                "SOPS_DISABLE_VERSION_CHECK": "1",
                "AWS_EC2_METADATA_DISABLED": "true",
                "GNUPGHOME": directory,
            }
            encrypting = operation == "encrypt"
            command = [
                self.binary, "--config", str(config), "--" + operation,
                "--input-type", "json" if encrypting else "yaml",
                "--output-type", "yaml" if encrypting else "json",
            ]
            if encrypting:
                command += ["--age", self.recipient, "--encrypted-regex", ".*"]
            command.append("/dev/stdin")

            try:
                result = subprocess.run(
                    command, input=data, capture_output=True,
                    env=environment, cwd=directory, timeout=20,
                )
            except (OSError, subprocess.TimeoutExpired):
                raise Error(f"SOPS {operation} could not complete.") from None
            if result.returncode:
                # Diagnostics can contain document values; never relay them.
                raise Error(f"SOPS {operation} failed; check the file, recipient, and identity.")
            return result.stdout
