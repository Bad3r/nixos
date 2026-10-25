# Copyright (c) 2026 Bad3r
"""Grant policy: what a request may open and which paths it renders."""

import ipaddress
import unittest

from workloads.grants import (
    GrantError,
    Path,
    Policy,
    Ports,
    Route,
    Target,
    format_duration,
    parse_duration,
)

from tests.fixtures import POLICY, policy


def address(text: str) -> ipaddress.IPv4Address:
    """Shorthand for an IPv4 address."""
    return ipaddress.IPv4Address(text)


class DurationTest(unittest.TestCase):
    """TTLs read and print in s, m, h, and d."""

    def test_parse(self) -> None:
        """Every unit and a bare number of seconds parse."""
        self.assertEqual(
            [parse_duration(text) for text in ("90", "90s", "30m", "2h", "1d")],
            [90, 90, 1800, 7200, 86400],
        )
        for text in ("0", "2x", "-1m", "", "1.5h"):
            with self.assertRaises(GrantError, msg=text) as caught:
                parse_duration(text)
            self.assertEqual(caught.exception.code, "invalid-argument")

    def test_format(self) -> None:
        """Whole units print short; the rest print hours and minutes."""
        self.assertEqual(
            [format_duration(seconds) for seconds in (86400, 7200, 1800, 5400, 90, 5)],
            ["1d", "2h", "30m", "1h30m", "1m30s", "5s"],
        )


class TargetTest(unittest.TestCase):
    """Targets share the link grammar and refuse sandboxes."""

    def test_forms(self) -> None:
        """A port is optional and UDP is marked."""
        self.assertEqual(Target.parse("host:dev"), Target("host", "dev", None))
        self.assertEqual(
            Target.parse("guest:win11:3389"), Target("guest", "win11", Ports("tcp", 3389, 3389))
        )
        self.assertEqual(str(Target.parse("service:dns:53/udp")), "service:dns:53/udp")

    def test_refusals(self) -> None:
        """Sandboxes, bare addresses, unknown kinds, and port 0 are no targets."""
        for text in ("sbx-ab12", "10.0.0.1:22", "lan:router", "host:dev:0", "host:dev:70000"):
            with self.assertRaises(GrantError, msg=text) as caught:
                Target.parse(text)
            self.assertEqual(caught.exception.code, "invalid-target")


class SourceTest(unittest.TestCase):
    """Sandboxes bring an address on a sandbox network; guests come from the policy."""

    def test_sandbox(self) -> None:
        """A free address on a sandbox network resolves to that network."""
        (interface,) = policy().resolve_source("sbx-ab12", "172.16.2.50")
        self.assertEqual(
            (interface.network.bridge, interface.address), ("vn-sbx", address("172.16.2.50"))
        )

    def test_sandbox_refusals(self) -> None:
        """Gateways, reserved, foreign, and non-sandbox addresses are refused."""
        for claimed in (
            "172.16.2.1",
            "172.16.2.0",
            "172.16.2.255",
            "172.16.2.9",
            "172.16.1.50",
            "10.0.0.5",
        ):
            with self.assertRaises(GrantError, msg=claimed) as caught:
                policy().resolve_source("sbx-ab12", claimed)
            self.assertEqual(caught.exception.code, "invalid-source")
        with self.assertRaises(GrantError) as caught:
            policy().resolve_source("sbx-ab12", None)
        self.assertEqual(caught.exception.code, "no-address")

    def test_guest(self) -> None:
        """A guest named by a rule resolves from the policy; others are refused."""
        (interface,) = policy().resolve_source("guest:dev", None)
        self.assertEqual(interface.address, address("172.16.1.10"))
        cases = {
            ("guest:web", None): "not-allowed",
            ("guest:dev", "172.16.1.10"): "invalid-request",
            ("dev", None): "invalid-source",
            ("network:lan", None): "invalid-source",
        }
        for (source, claimed), code in cases.items():
            with self.assertRaises(GrantError, msg=source) as caught:
                policy().resolve_source(source, claimed)
            self.assertEqual(caught.exception.code, code)


class RuleTest(unittest.TestCase):
    """Rules name sources by pattern and targets with or without a port."""

    def test_max_ttl(self) -> None:
        """The matching rule sets the bound; unmatched pairs are refused."""
        self.assertEqual(policy().max_ttl("sbx-ab12", Target.parse("host:dev:8080")), 7200)
        self.assertEqual(policy().max_ttl("guest:dev", Target.parse("host:dev")), 86400)
        self.assertEqual(policy().max_ttl("sbx-ab12", Target.parse("guest:dev:8080")), 7200)
        for source, target in (
            ("guest:dev", "host:api"),
            ("sbx-ab12", "guest:dev"),
            ("sbx-ab12", "guest:web:80"),
        ):
            with self.assertRaises(GrantError, msg=f"{source} {target}") as caught:
                policy().max_ttl(source, Target.parse(target))
            self.assertEqual(caught.exception.code, "not-allowed")

    def test_malformed(self) -> None:
        """A policy missing a key fails with its own code."""
        broken = dict(POLICY)
        del broken["reserved"]
        with self.assertRaises(GrantError) as caught:
            Policy.from_json(broken)
        self.assertEqual(caught.exception.code, "policy-file")


class PathTest(unittest.TestCase):
    """A grant opens exactly the requested ports between the two addresses."""

    def sandbox(self) -> Policy:
        """The fixture policy."""
        return policy()

    def test_host(self) -> None:
        """A host service sits at the source network's gateway."""
        current = self.sandbox()
        interfaces = current.resolve_source("sbx-ab12", "172.16.2.50")
        self.assertEqual(
            current.paths(interfaces, Target.parse("host:dev")),
            [
                Path(
                    "vn-sbx",
                    address("172.16.2.50"),
                    address("172.16.2.1"),
                    Ports("tcp", 8000, 8999),
                )
            ],
        )
        (single,) = current.paths(interfaces, Target.parse("host:dev:8080"))
        self.assertEqual(single.ports, Ports("tcp", 8080, 8080))
        self.assertEqual(current.routes(single), [])

    def test_ungrantable(self) -> None:
        """Ports outside the target's grantable ones and unknown targets are refused."""
        current = self.sandbox()
        interfaces = current.resolve_source("sbx-ab12", "172.16.2.50")
        for target in ("host:dev:9000", "host:dev:8080/udp", "guest:dev:8081", "host:secret"):
            with self.assertRaises(GrantError, msg=target) as caught:
                current.paths(interfaces, Target.parse(target))
            self.assertEqual(caught.exception.code, "not-grantable")

    def test_guest_across_networks(self) -> None:
        """A guest on another network gets its address and a route each way."""
        current = self.sandbox()
        interfaces = current.resolve_source("sbx-ab12", "172.16.2.50")
        (path,) = current.paths(interfaces, Target.parse("guest:dev:8080"))
        self.assertEqual(path.destination, address("172.16.1.10"))
        self.assertEqual(
            current.routes(path),
            [
                Route("vn-sbx", address("172.16.2.50"), address("172.16.1.10")),
                Route("vn-desktop", address("172.16.1.10"), address("172.16.2.50")),
            ],
        )

    def test_same_network(self) -> None:
        """Same-network peers either already talk or are isolated by the bridge."""
        current = self.sandbox()
        guest = current.resolve_source("guest:dev", None)
        with self.assertRaises(GrantError) as caught:
            current.paths(guest, Target.parse("guest:web:80"))
        self.assertEqual(caught.exception.code, "already-reachable")
        isolated = Policy.from_json(
            POLICY
            | {
                "targets": {
                    "guest": {
                        "box": {
                            "interfaces": [{"network": "sbx", "address": "172.16.2.9"}],
                            "ports": [{"from": 22, "to": 22, "proto": "tcp"}],
                        }
                    }
                }
            }
        )
        sandbox = isolated.resolve_source("sbx-ab12", "172.16.2.50")
        with self.assertRaises(GrantError) as caught:
            isolated.paths(sandbox, Target.parse("guest:box:22"))
        self.assertIn("isolatePeers", str(caught.exception))

    def test_conflicts(self) -> None:
        """Overlapping ranges on the same addresses conflict; other protocols do not."""
        base = Path(
            "vn-sbx", address("172.16.2.50"), address("172.16.2.1"), Ports("tcp", 8000, 8999)
        )
        self.assertTrue(
            base.conflicts(
                Path(base.bridge, base.source, base.destination, Ports("tcp", 8080, 8080))
            )
        )
        self.assertFalse(
            base.conflicts(
                Path(base.bridge, base.source, base.destination, Ports("udp", 8080, 8080))
            )
        )
        self.assertFalse(
            base.conflicts(Path(base.bridge, address("172.16.2.51"), base.destination, base.ports))
        )
