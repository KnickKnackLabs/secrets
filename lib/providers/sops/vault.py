"""Private-file policy, cooperating locks, and atomic ciphertext publication."""

import contextlib
import fcntl
import os
from pathlib import Path
import stat
import tempfile

from document import Error
from .encryption import EncryptedDocument


def configured_path(name):
    value = os.environ.get(name, "")
    if not value or not Path(value).is_absolute():
        raise Error(f"{name} must be an explicit absolute path.")
    path = Path(value)
    # Parent aliases share one lock. Keep the final component for symlink checks.
    return path.parent.resolve(strict=True) / path.name


def private_file(path):
    info = path.lstat()
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o077
        or info.st_nlink != 1
    ):
        raise Error("Vault and identity must be owner-only, singly linked regular files.")


@contextlib.contextmanager
def vault_lock(path, writing):
    # The sidecar remains stable when a write replaces the vault inode.
    parent = path.parent.stat()
    if parent.st_uid != os.getuid() or parent.st_mode & 0o022:
        raise Error("Vault directory must be owned by you and not writable by others.")
    fd = os.open(str(path) + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
            or info.st_nlink != 1
        ):
            raise Error("Unsafe vault lock file.")
        mode = fcntl.LOCK_EX if writing else fcntl.LOCK_SH
        try:
            fcntl.flock(fd, mode | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Error("Vault is busy; retry after the other operation finishes.") from None
        yield
    finally:
        os.close(fd)


class Vault:
    """Load one snapshot and publish verified ciphertext without clobbering edits."""

    def __init__(self):
        self.path = configured_path("SECRETS_SOPS_FILE")
        identity = configured_path("SECRETS_SOPS_AGE_KEY_FILE")
        private_file(identity)
        if self.path == identity:
            raise Error("Vault and identity must be different files.")
        self.document = EncryptedDocument(
            identity,
            os.environ.get("SECRETS_SOPS_RECIPIENT", ""),
            os.environ.get("SECRETS_SOPS_BINARY", "sops"),
        )
        self.original = None

    def load(self, allow_missing=False):
        try:
            private_file(self.path)
        except FileNotFoundError:
            if allow_missing:
                return {}
            raise Error("SOPS vault does not exist.") from None
        self.original = self.path.read_bytes()
        return self.document.decrypt(self.original)

    def save(self, values):
        ciphertext = self.document.encrypt(values)
        # Only verified ciphertext reaches disk, on the destination filesystem.
        fd, filename = tempfile.mkstemp(prefix=".secrets-", suffix=".enc", dir=self.path.parent)
        temporary = Path(filename)
        try:
            with os.fdopen(fd, "wb") as output:
                output.write(ciphertext)
                output.flush()
                os.fsync(output.fileno())
            self._publish(temporary)
        finally:
            temporary.unlink(missing_ok=True)

    def _publish(self, temporary):
        if self.original is None:
            # Atomic no-clobber creation also refuses a dangling symlink target.
            os.link(temporary, self.path)
        else:
            private_file(self.path)
            if self.path.read_bytes() != self.original:
                raise Error("Vault changed outside Secrets; refusing to overwrite it.")
            os.replace(temporary, self.path)
