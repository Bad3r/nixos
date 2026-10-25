# Copyright (c) 2026 Bad3r
"""Publishing copies out on the host without replacing anything."""

import ctypes
import errno
import os
import secrets
import shutil
from typing import TYPE_CHECKING

from sbx.errors import SbxError

if TYPE_CHECKING:
    from pathlib import Path


AT_FDCWD = -100
RENAME_NOREPLACE = 1


def _rename_noreplace(source: Path, target: Path) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = libc.renameat2
    renameat2.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameat2.restype = ctypes.c_int
    if renameat2(AT_FDCWD, os.fsencode(source), AT_FDCWD, os.fsencode(target), RENAME_NOREPLACE):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(target))


def _remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def publish(staged: Path, target: Path) -> None:
    """Move a staged copy to a target that must not exist, never replacing one."""
    try:
        try:
            _rename_noreplace(staged, target)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            # Another filesystem: copy beside the target, then rename there.
            beside = target.with_name(f".sbx-{secrets.token_hex(4)}")
            try:
                if staged.is_dir():
                    shutil.copytree(staged, beside, symlinks=True)
                else:
                    shutil.copy2(staged, beside, follow_symlinks=False)
                _rename_noreplace(beside, target)
            finally:
                _remove(beside)
    except OSError as error:
        if error.errno == errno.EEXIST:
            msg = f"{target} exists; copies out never overwrite"
            raise SbxError(msg, code="exists") from error
        raise
