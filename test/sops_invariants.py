#!/usr/bin/env python3
"""Lower-boundary SOPS invariants; public fake identities, real encryption."""

import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "lib"))
from providers.sops import vault as sops
from providers.sops.encryption import parse_values

FIXTURES = REPO / "test/fixtures/sops"


class VaultTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="fake-secrets-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.identity = self.root / "identity.txt"
        shutil.copyfile(FIXTURES / "identity.txt", self.identity)
        self.identity.chmod(0o600)
        self.path = self.root / "vault.enc.yaml"
        environment = patch.dict(os.environ, {
            "SECRETS_SOPS_FILE": str(self.path),
            "SECRETS_SOPS_AGE_KEY_FILE": str(self.identity),
            "SECRETS_SOPS_RECIPIENT": (FIXTURES / "recipient.txt").read_text().strip(),
        })
        environment.start()
        self.addCleanup(environment.stop)

    def create(self):
        vault = sops.Vault()
        with sops.vault_lock(vault.path, True):
            self.assertEqual(vault.load(allow_missing=True), {})
            vault.save({"fake/key": "FAKE-ONLY-SENTINEL\n\n"})
        return vault

    def assert_no_temporaries(self):
        self.assertEqual(list(self.root.glob(".secrets-*.enc")), [])

    def test_round_trip_and_ciphertext_permissions(self):
        self.create()
        self.assertEqual(sops.Vault().load(), {"fake/key": "FAKE-ONLY-SENTINEL\n\n"})
        self.assertNotIn(b"FAKE-ONLY-SENTINEL", self.path.read_bytes())
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.path.stat().st_nlink, 1)
        self.assert_no_temporaries()

    def test_wrong_identity_and_recipient_preserve_ciphertext(self):
        self.create()
        original = self.path.read_bytes()
        other = self.root / "other.txt"
        shutil.copyfile(FIXTURES / "other-identity.txt", other)
        other.chmod(0o600)
        with patch.dict(os.environ, {"SECRETS_SOPS_AGE_KEY_FILE": str(other)}):
            with self.assertRaises(sops.Error):
                sops.Vault().load()
        with patch.dict(os.environ, {"SECRETS_SOPS_RECIPIENT":
                                    (FIXTURES / "other-recipient.txt").read_text().strip()}):
            vault = sops.Vault()
            vault.load()
            with self.assertRaises(sops.Error):
                vault.save({"changed": "fake"})
        self.assertEqual(self.path.read_bytes(), original)
        self.assert_no_temporaries()

    def test_tampered_ciphertext_fails_authentication(self):
        self.create()
        # Corrupt authenticated encrypted data, not plaintext or a key fixture.
        data = self.path.read_bytes()
        offset = data.index(b"data:") + len(b"data:")
        replacement = b"B" if data[offset:offset + 1] == b"A" else b"A"
        self.path.write_bytes(data[:offset] + replacement + data[offset + 1:])
        with self.assertRaises(sops.Error):
            sops.Vault().load()

    def test_private_files_and_native_identity_required(self):
        self.create()
        for path in (self.identity, self.path):
            path.chmod(0o644)
            with self.assertRaises(sops.Error):
                sops.Vault().load()
            path.chmod(0o600)
        self.identity.write_text("AGE-PLUGIN-FAKE-NOT-AN-IDENTITY\n")
        with self.assertRaises(sops.Error):
            sops.Vault()

    def test_identity_alias_is_rejected(self):
        with patch.dict(os.environ, {"SECRETS_SOPS_FILE": str(self.identity)}):
            with self.assertRaises(sops.Error):
                sops.Vault()

    def test_symlinks_and_hardlinks_cannot_be_vaults(self):
        self.path.symlink_to(self.root / "missing")
        with self.assertRaises(sops.Error):
            sops.Vault().load(allow_missing=True)
        self.path.unlink()
        self.create()
        os.link(self.path, self.root / "alias")
        with self.assertRaises(sops.Error):
            sops.Vault().load()

    def test_parent_aliases_share_lock_and_busy_fails_closed(self):
        alias = self.root / "parent-alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with sops.vault_lock(self.path, True):
            with patch.dict(os.environ, {"SECRETS_SOPS_FILE": str(alias / self.path.name)}):
                vault = sops.Vault()
                self.assertEqual(vault.path, self.path.resolve())
                with self.assertRaises(sops.Error):
                    with sops.vault_lock(vault.path, False):
                        self.fail("second reader entered during exclusive lock")
        with sops.vault_lock(self.path, False):
            with sops.vault_lock(self.path, False):
                pass
            with self.assertRaises(sops.Error):
                with sops.vault_lock(self.path, True):
                    self.fail("writer entered during shared lock")

    def test_unsafe_parent_and_lock_fail_closed(self):
        self.root.chmod(0o777)
        try:
            with self.assertRaises(sops.Error):
                with sops.vault_lock(self.path, True):
                    self.fail("unsafe directory accepted")
        finally:
            self.root.chmod(0o700)
        lock = Path(str(self.path) + ".lock")
        lock.symlink_to(self.identity)
        with self.assertRaises(OSError):
            with sops.vault_lock(self.path, True):
                self.fail("symlink lock accepted")

    def test_encrypt_and_publish_failures_preserve_original(self):
        vault = self.create()
        vault.load()
        original = self.path.read_bytes()
        with patch.object(vault.document, "encrypt", side_effect=sops.Error("fake encrypt failure")):
            with self.assertRaises(sops.Error):
                vault.save({"other": "fake"})
        self.assertEqual(self.path.read_bytes(), original)
        with patch("providers.sops.vault.os.replace", side_effect=OSError("fake publication failure")):
            with self.assertRaises(OSError):
                vault.save({"other": "fake"})
        self.assertEqual(self.path.read_bytes(), original)
        self.assert_no_temporaries()

    def test_no_clobber_and_external_change_detection(self):
        vault = sops.Vault()
        vault.load(allow_missing=True)
        self.path.write_bytes(b"external fake file")
        with self.assertRaises(FileExistsError):
            vault.save({"fake": "value"})
        self.assertEqual(self.path.read_bytes(), b"external fake file")
        self.path.unlink()
        vault = self.create()
        vault.load()
        self.path.write_bytes(b"external edit")
        with self.assertRaises(sops.Error):
            vault.save({"fake": "value"})
        self.assertEqual(self.path.read_bytes(), b"external edit")
        self.assert_no_temporaries()

    def test_invalid_bundles_are_rejected(self):
        for document in (b'{"a":1}', b'{"a":"1","a":"2"}', b'[]',
                         b'{"sops":"reserved"}', b'{"bad\\nname":"x"}',
                         b'{"a":"\\ud800"}'):
            with self.subTest(document=document), self.assertRaises(sops.Error):
                parse_values(document)


if __name__ == "__main__":
    unittest.main()
