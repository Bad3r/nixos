# Copyright (c) 2026 Bad3r
"""The libvirt backend against domains that vanish under it."""

import unittest
from typing import Any

from sbx import backend
from sbx.core import SbxError

libvirt = backend.libvirt

XML = """<domain><name>{name}</name><memory>2097152</memory><vcpu>2</vcpu><metadata/></domain>"""


class Error(libvirt.libvirtError):
    """A libvirt error with a chosen code."""

    def __init__(self, code: int) -> None:
        """Carry the code without consulting libvirt's last error."""
        Exception.__init__(self, f"libvirt error {code}")
        self.code = code

    def get_error_code(self) -> int:
        """Return the chosen code."""
        return self.code


class Handle:
    """A domain whose calls succeed until the named method fails."""

    def __init__(self, name: str, fail: str | None = None, code: int = 0) -> None:
        """Fail `fail` with `code` when set."""
        self._name = name
        self.fail = fail
        self.code = code or libvirt.VIR_ERR_NO_DOMAIN
        self.calls: list[str] = []

    def _call(self, method: str) -> None:
        self.calls.append(method)
        if method == self.fail:
            raise Error(self.code)

    def name(self) -> str:
        """Return the name."""
        return self._name

    def XMLDesc(self, _flags: int) -> str:  # noqa: N802
        """Return a minimal definition."""
        self._call("XMLDesc")
        return XML.format(name=self._name)

    def state(self) -> list[int]:
        """Report running."""
        self._call("state")
        return [1, 0]

    def isActive(self) -> int:  # noqa: N802
        """Report active."""
        self._call("isActive")
        return 1

    def hasManagedSaveImage(self, _flags: int) -> int:  # noqa: N802
        """Report no saved state."""
        self._call("hasManagedSaveImage")
        return 0

    def destroy(self) -> None:
        """Stop the domain."""
        self._call("destroy")

    def undefineFlags(self, _flags: int) -> None:  # noqa: N802
        """Undefine the domain."""
        self._call("undefineFlags")


class Connection:
    """A session connection over a fixed set of handles."""

    def __init__(self, *handles: Handle) -> None:
        """Hold the handles by name."""
        self.handles = {handle.name(): handle for handle in handles}

    def listAllDomains(self, _flags: int) -> list[Handle]:  # noqa: N802
        """Return every handle."""
        return list(self.handles.values())

    def lookupByName(self, name: str) -> Handle:  # noqa: N802
        """Return a handle, or fail as libvirt does for an unknown name."""
        if name not in self.handles:
            raise Error(libvirt.VIR_ERR_NO_DOMAIN)
        return self.handles[name]


def _backend(*handles: Handle) -> Any:  # noqa: ANN401
    instance: Any = backend.LibvirtBackend.__new__(backend.LibvirtBackend)
    instance._conn = Connection(*handles)  # noqa: SLF001
    return instance


class DomainsTest(unittest.TestCase):
    """A domain another client removes never fails an operation on the others."""

    def test_vanished_domain_skipped(self) -> None:
        """A domain gone during any per-domain call drops out of the listing."""
        for method in ("XMLDesc", "state", "isActive", "hasManagedSaveImage"):
            with self.subTest(method=method):
                listed = _backend(Handle("sbx-a"), Handle("sbx-b", fail=method), Handle("sbx-c"))
                self.assertEqual([d.name for d in listed.domains()], ["sbx-a", "sbx-c"])

    def test_other_errors_raise(self) -> None:
        """Any other failure still fails the listing."""
        listed = _backend(
            Handle("sbx-a"), Handle("sbx-b", "XMLDesc", libvirt.VIR_ERR_INTERNAL_ERROR)
        )
        with self.assertRaises(SbxError) as raised:
            listed.domains()
        self.assertEqual(raised.exception.code, "libvirt")

    def test_domain_lookup(self) -> None:
        """One domain is described alone; a missing or vanishing one is None."""
        other = Handle("sbx-other")
        found = _backend(Handle("sbx-a"), other).domain("sbx-a")
        self.assertEqual(found.name, "sbx-a")
        self.assertEqual(found.memory_mib, 2048)
        self.assertEqual(other.calls, [])
        self.assertIsNone(_backend().domain("sbx-a"))
        self.assertIsNone(_backend(Handle("sbx-a", fail="isActive")).domain("sbx-a"))

    def test_remove_vanished(self) -> None:
        """Removing a domain that is already gone succeeds."""
        _backend().remove("sbx-a")
        _backend(Handle("sbx-a", fail="undefineFlags")).remove("sbx-a")
        busy = _backend(Handle("sbx-a", "destroy", libvirt.VIR_ERR_OPERATION_FAILED))
        with self.assertRaises(SbxError) as raised:
            busy.remove("sbx-a")
        self.assertEqual(raised.exception.code, "libvirt")

    def test_missing_lookup_is_not_found(self) -> None:
        """Per-domain operations on a missing domain raise not-found."""
        with self.assertRaises(SbxError) as raised:
            _backend().live_xml("sbx-a")
        self.assertEqual(raised.exception.code, "not-found")
