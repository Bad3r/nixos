# Copyright (c) 2026 Bad3r
"""workload-grantd: request grammar, decisions, journal order, and kernel commands."""

import contextlib
import ipaddress
import itertools
import json
import unittest
from typing import TYPE_CHECKING, cast

from workloads.grantd import Caller, Element, Flow, NftKernel, Service, Tools
from workloads.grants import GrantError, Path, Ports, Record, Route

from tests.fixtures import SANDBOX_MAC, policy, read_leases

if TYPE_CHECKING:
    from collections.abc import Generator, Sequence

MAC = SANDBOX_MAC
CALLER = Caller(pid=4242, uid=1000, cmdline="workloads grant sbx-ab12 host:dev")
SANDBOX = ipaddress.IPv4Address("172.16.2.50")
GATEWAY = ipaddress.IPv4Address("172.16.2.1")
DEV = ipaddress.IPv4Address("172.16.1.10")


class FakeKernel:
    """In-memory set, conntrack table, and rule list; every write lands in `events`."""

    def __init__(self, events: list[str]) -> None:
        """Start empty."""
        self.events = events
        self.live: list[Element] = []
        self.conntrack: list[Flow] = []
        self.rules: set[Route] = set()
        self.sources: dict[tuple[str, str, ipaddress.IPv4Address], int] = {}

    def elements(self) -> list[Element]:
        """Live elements."""
        return list(self.live)

    def add(self, elements: Sequence[Element], ttl: int, source_ttl: int) -> None:
        """Record the add."""
        self.events.append(f"add {len(elements)} ttl={ttl}")
        self.live.extend(elements)
        for element in elements:
            self.sources[element.path.bridge, element.path.mac, element.path.source] = source_ttl

    def remove(self, elements: Sequence[Element], sources: Sequence[Path]) -> None:
        """Record the removal."""
        self.events.append(f"remove {len(elements)}")
        self.live = [element for element in self.live if element not in elements]
        for path in sources:
            del self.sources[path.bridge, path.mac, path.source]

    def flows(self, path: Path) -> list[Flow]:
        """Flows between the path's addresses on its ports."""
        return [
            flow
            for flow in self.conntrack
            if (flow.source, flow.destination) == (str(path.source), str(path.destination))
            and path.ports.first <= flow.dport <= path.ports.last
        ]

    def drop_flow(self, flow: Flow) -> None:
        """Record the deletion."""
        self.events.append(f"drop {flow.dport}")
        self.conntrack.remove(flow)

    def routes(self, preference: int) -> set[Route]:
        """Rules at the preference."""
        self.events.append(f"routes {preference}")
        return set(self.rules)

    def add_route(self, preference: int, route: Route) -> None:
        """Record the rule."""
        del preference
        self.events.append(f"route+ {route.bridge}")
        self.rules.add(route)

    def delete_route(self, preference: int, route: Route) -> None:
        """Record the rule's removal."""
        del preference
        self.events.append(f"route- {route.bridge}")
        self.rules.discard(route)


class Harness:
    """A service over a fake kernel with its journal entries and events."""

    def __init__(self) -> None:
        """Wire the service to fakes."""
        self.events: list[str] = []
        self.journal: list[dict[str, object]] = []
        self.kernel = FakeKernel(self.events)
        self.fail_journal = False
        ids = (f"{number:08x}" for number in itertools.count(1))
        self.service = Service(
            policy,
            self.kernel,
            self.log,
            self.lock,
            new_id=lambda: next(ids),
            read_text=read_leases,
        )

    def log(self, message: str, fields: dict[str, object]) -> None:
        """Keep the entry, or fail like a missing journal socket."""
        if self.fail_journal:
            raise FileNotFoundError(message)
        self.events.append(f"journal {fields['decision']}")
        self.journal.append(fields | {"message": message})

    @contextlib.contextmanager
    def lock(self) -> Generator[None]:
        """Record the critical section."""
        self.events.append("lock")
        yield
        self.events.append("unlock")

    def ask(self, request: object) -> Record:
        """Send one JSON request."""
        return self.service.handle(json.dumps(request).encode(), CALLER)

    def grant(
        self, target: str, ttl: int = 600, source: str = "sbx-ab12", **extra: object
    ) -> Record:
        """Request a grant, from the fixture sandbox by default."""
        request: dict[str, object] = {
            "verb": "grant",
            "source": source,
            "target": target,
            "ttl": ttl,
        }
        if source.startswith("sbx-"):
            request["address"] = str(SANDBOX)
        return self.ask(request | extra)


def code(answer: Record) -> str | None:
    """The error code of an answer, if any."""
    error = answer.get("error")
    return cast("str", cast("Record", error)["code"]) if isinstance(error, dict) else None


class GrantTest(unittest.TestCase):
    """Grants add elements under the lock after the journal records them."""

    def test_grant(self) -> None:
        """A host grant adds one element with the TTL and no route."""
        harness = Harness()
        answer = harness.grant("host:dev:8080", ttl=900)
        grant = cast("Record", answer["grant"])
        self.assertEqual(
            (grant["id"], grant["target"], grant["expires_in"]), ("00000001", "host:dev:8080", 900)
        )
        self.assertEqual(
            harness.events, ["lock", "journal granted", "routes 30900", "add 1 ttl=900", "unlock"]
        )
        (element,) = harness.kernel.live
        self.assertEqual(
            element.path, Path("vn-sbx", MAC, SANDBOX, GATEWAY, Ports("tcp", 8080, 8080))
        )
        self.assertEqual(element.comment, f"00000001 sbx-ab12 host:dev:8080 {MAC}")
        entry = harness.journal[0]
        self.assertEqual(
            (entry["caller_pid"], entry["caller_uid"], entry["verb"], entry["address"]),
            (4242, 1000, "grant", SANDBOX),
        )

    def test_session(self) -> None:
        """The client's agent session reaches the journal."""
        harness = Harness()
        harness.grant("host:api", session="claude:abc")
        self.assertEqual(harness.journal[0]["session"], "claude:abc")

    def test_guest_route(self) -> None:
        """A grant to a guest on another network adds a route each way."""
        harness = Harness()
        harness.grant("guest:dev:8080")
        self.assertEqual(
            harness.kernel.rules,
            {Route("vn-sbx", SANDBOX, DEV), Route("vn-desktop", DEV, SANDBOX)},
        )

    def test_refusals_change_nothing(self) -> None:
        """Refused grants journal the refusal and never reach the kernel."""
        harness = Harness()
        cases = {
            "ttl": harness.grant("host:dev", ttl=7201),
            "not-allowed": harness.grant("host:api", source="guest:dev"),
            "not-grantable": harness.grant("host:dev:9000"),
            "invalid-target": harness.grant("sbx-peer"),
        }
        self.assertEqual(
            {key: code(answer) for key, answer in cases.items()}, {key: key for key in cases}
        )
        self.assertEqual(harness.kernel.live, [])
        self.assertEqual({entry["decision"] for entry in harness.journal}, {"refused"})
        self.assertEqual(
            (
                harness.journal[0]["source"],
                harness.journal[0]["target"],
                harness.journal[0]["error"],
            ),
            ("sbx-ab12", "host:dev", "ttl"),
        )

    def test_conflict(self) -> None:
        """An overlapping grant is refused with the holder's id."""
        harness = Harness()
        harness.grant("host:dev")
        answer = harness.grant("host:dev:8080")
        self.assertEqual(code(answer), "conflict")
        self.assertIn("00000001", str(answer["error"]))

    def test_max_concurrent(self) -> None:
        """A source holds at most maxConcurrent grants; other sources are unaffected."""
        harness = Harness()
        harness.grant("host:dev:8000")
        harness.grant("host:dev:8001")
        self.assertEqual(code(harness.grant("host:dev:8002")), "max-concurrent")
        self.assertIsNone(code(harness.grant("host:dev:8002", source="guest:dev")))

    def test_journal_failure(self) -> None:
        """Without the journal nothing is applied."""
        harness = Harness()
        harness.fail_journal = True
        self.assertEqual(code(harness.grant("host:dev")), "journal")
        self.assertEqual(harness.kernel.live, [])

    def test_stale_routes(self) -> None:
        """Routes whose grant expired go with the next change."""
        harness = Harness()
        harness.kernel.rules.add(Route("vn-sbx", SANDBOX, ipaddress.IPv4Address("172.16.1.99")))
        harness.grant("host:dev")
        self.assertEqual(harness.kernel.rules, set())


class IdentityTest(unittest.TestCase):
    """A sandbox is its leased address and MAC, whatever name a caller gives."""

    def test_count_by_address(self) -> None:
        """Renaming the source does not reset maxConcurrent."""
        harness = Harness()
        harness.grant("host:dev:8000", source="sbx-n0")
        harness.grant("host:dev:8001", source="sbx-n1")
        self.assertEqual(code(harness.grant("host:dev:8002", source="sbx-n2")), "max-concurrent")

    def test_revoke_by_address(self) -> None:
        """Revoking a source takes the grants at the source's address under any name."""
        harness = Harness()
        harness.grant("host:dev:8000", source="sbx-n0")
        answer = harness.ask({"verb": "revoke", "source": "sbx-n1", "address": str(SANDBOX)})
        self.assertEqual(answer, {"revoked": ["00000001"]})

    def test_moved_lease(self) -> None:
        """A new MAC at an address whose earlier holder still has grants is refused."""
        harness = Harness()
        harness.grant("host:dev:8000")
        moved = json.dumps(
            [{"ip-address": "172.16.2.50", "mac-address": "52:54:00:00:02:99", "expiry-time": 0}]
        )

        def read_moved(path: str) -> str:
            del path
            return moved

        harness.service.read_text = read_moved
        answer = harness.grant("host:dev:8001")
        self.assertEqual(code(answer), "conflict")
        self.assertIn("another MAC", str(answer["error"]))

    def test_source_lifetime(self) -> None:
        """The source outlives its longest grant and goes with its last one."""
        harness = Harness()
        harness.grant("host:dev:8000", ttl=900)
        harness.grant("host:dev:8001", ttl=60)
        place = ("vn-sbx", MAC, SANDBOX)
        # The fake lists the full TTL as remaining; the helper adds the rounding second.
        self.assertEqual(harness.kernel.sources[place], 901)
        harness.ask({"verb": "revoke", "id": "00000001"})
        self.assertIn(place, harness.kernel.sources)
        harness.ask({"verb": "revoke", "id": "00000002"})
        self.assertNotIn(place, harness.kernel.sources)

    def test_no_lease(self) -> None:
        """An address no live lease holds is refused."""
        harness = Harness()
        answer = harness.grant("host:dev", address="172.16.2.51")
        self.assertEqual(code(answer), "no-lease")
        self.assertEqual(harness.kernel.live, [])


class RevokeTest(unittest.TestCase):
    """Revoking deletes the elements, their conntrack entries, and their routes."""

    def test_revoke(self) -> None:
        """Only flows on the revoked ports go."""
        harness = Harness()
        harness.grant("guest:dev:8080")
        harness.grant("host:dev:8000")
        harness.kernel.conntrack = [
            Flow("tcp", str(SANDBOX), str(DEV), 40000, 8080),
            Flow("tcp", str(SANDBOX), str(GATEWAY), 40001, 8000),
        ]
        harness.events.clear()
        answer = harness.ask({"verb": "revoke", "id": "00000001"})
        self.assertEqual(answer, {"revoked": ["00000001"]})
        self.assertEqual(
            harness.events,
            [
                "lock",
                "journal revoked",
                "remove 1",
                "drop 8080",
                "routes 30900",
                "route- vn-desktop",
                "route- vn-sbx",
                "unlock",
            ],
        )
        self.assertEqual([flow.dport for flow in harness.kernel.conntrack], [8000])

    def test_revoke_all(self) -> None:
        """--all takes every grant of one source and leaves the others."""
        harness = Harness()
        harness.grant("host:dev:8000")
        harness.grant("host:api")
        harness.grant("host:dev", source="guest:dev")
        answer = harness.ask({"verb": "revoke", "source": "sbx-ab12"})
        self.assertEqual(answer, {"revoked": ["00000001", "00000002"]})
        self.assertEqual([element.source for element in harness.kernel.live], ["guest:dev"])
        self.assertEqual(harness.ask({"verb": "revoke", "source": "sbx-gone"}), {"revoked": []})

    def test_unknown(self) -> None:
        """An unknown id is an error; a malformed one never reaches the kernel."""
        harness = Harness()
        self.assertEqual(code(harness.ask({"verb": "revoke", "id": "0000beef"})), "not-found")
        self.assertEqual(
            code(harness.ask({"verb": "revoke", "id": "x; flush ruleset"})), "invalid-request"
        )
        self.assertEqual(
            code(harness.ask({"verb": "revoke", "source": "10.0.0.1"})), "invalid-source"
        )


class GrammarTest(unittest.TestCase):
    """Only the three verbs with exactly their keys are accepted."""

    def test_list(self) -> None:
        """Listing groups elements by grant."""
        harness = Harness()
        harness.grant("host:dev")
        (listed,) = cast("list[Record]", harness.ask({"verb": "list"})["grants"])
        self.assertEqual((listed["source"], listed["target"]), ("sbx-ab12", "host:dev"))
        self.assertEqual(cast("list[Record]", listed["paths"])[0]["ports"], "8000-8999")

    def test_malformed(self) -> None:
        """Garbage, extra keys, and odd types are refused."""
        harness = Harness()
        self.assertEqual(code(harness.service.handle(b"{", CALLER)), "invalid-request")
        requests: list[object] = [
            [],
            {"verb": "flush"},
            {"verb": "list", "rule": "accept"},
            {"verb": "grant", "source": "sbx-ab12", "target": "host:dev"},
            {"verb": "grant", "source": "sbx-ab12", "target": "host:dev", "ttl": True},
            {"verb": "grant", "source": "sbx-ab12", "target": "host:dev", "ttl": "1h"},
            {"verb": "grant", "source": 7, "target": "host:dev", "ttl": 60},
            {"verb": "revoke"},
            {"verb": "revoke", "id": "00000001", "source": "sbx-ab12"},
        ]
        for request in requests:
            self.assertEqual(code(harness.ask(request)), "invalid-request", request)
        self.assertEqual(harness.kernel.live, [])


LISTING = {
    "nftables": [
        {"metainfo": {"json_schema_version": 1}},
        {
            "set": {
                "family": "inet",
                "name": "grants",
                "table": "workload_grants",
                "elem": [
                    {
                        "elem": {
                            "val": {
                                "concat": [
                                    "vn-sbx",
                                    "172.16.2.50",
                                    "172.16.2.1",
                                    "tcp",
                                    {"range": [8000, 8999]},
                                ]
                            },
                            "timeout": 1800,
                            "expires": 1799,
                            "comment": "0000000a sbx-ab12 host:dev 52:54:00:00:02:50",
                        }
                    },
                    {
                        "elem": {
                            "val": {
                                "concat": [
                                    "vn-sbx",
                                    "172.16.2.50",
                                    "172.16.1.10",
                                    "udp",
                                    53,
                                ]
                            },
                            "timeout": 60,
                            "expires": 12,
                            "comment": "0000000b sbx-ab12 guest:dev:53/udp 52:54:00:00:02:50",
                        }
                    },
                ],
            }
        },
    ]
}

CONNTRACK = (
    "tcp      6 431999 ESTABLISHED src=172.16.2.50 dst=172.16.2.1 sport=40000 dport=8080"
    " src=172.16.2.1 dst=172.16.2.50 sport=8080 dport=40000 [ASSURED] mark=1048576 use=1\n"
    "tcp      6 431999 ESTABLISHED src=172.16.2.50 dst=172.16.2.1 sport=40001 dport=9000"
    " src=172.16.2.1 dst=172.16.2.50 sport=9000 dport=40001 [ASSURED] mark=1048576 use=1\n"
)


class Recorder:
    """A runner that answers from a script and keeps every call."""

    def __init__(self, answers: dict[str, tuple[int, str, str]]) -> None:
        """Answers keyed by the argument after the tool."""
        self.answers = answers
        self.calls: list[tuple[list[str], str | None]] = []

    def __call__(self, argv: Sequence[str], stdin: str | None) -> tuple[int, str, str]:
        """Record and answer."""
        self.calls.append((list(argv), stdin))
        key = " ".join(argv[1:3])
        return next(
            (answer for prefix, answer in self.answers.items() if key.startswith(prefix)),
            (0, "", ""),
        )


TOOLS = Tools(nft="/nft", conntrack="/conntrack", ip="/ip")
SET_NAME = "inet workload_grants grants"
SOURCES_NAME = "inet workload_grants sources"
SOURCE_KEY = '"vn-sbx" . 52:54:00:00:02:50 . 172.16.2.50'
KEY = '"vn-sbx" . 172.16.2.50 . 172.16.2.1 . tcp . 8000-8999'


class NftKernelTest(unittest.TestCase):
    """The commands the kernel adapter runs and the output it parses."""

    def test_elements(self) -> None:
        """Ranges and single ports parse, and the comment names the grant."""
        kernel = NftKernel(TOOLS, Recorder({"-j list": (0, json.dumps(LISTING), "")}))
        first, second = kernel.elements()
        self.assertEqual(
            (first.grant, first.path.ports, first.expires),
            ("0000000a", Ports("tcp", 8000, 8999), 1799),
        )
        self.assertEqual(
            (second.target, second.path.ports), ("guest:dev:53/udp", Ports("udp", 53, 53))
        )

    def test_foreign_element(self) -> None:
        """An element without a grant comment surfaces instead of being ignored."""
        listing = json.loads(json.dumps(LISTING))
        listing["nftables"][1]["set"]["elem"][0]["elem"]["comment"] = "by hand"
        kernel = NftKernel(TOOLS, Recorder({"-j list": (0, json.dumps(listing), "")}))
        with self.assertRaisesRegex(GrantError, "no grant comment"):
            kernel.elements()

    def test_missing_table(self) -> None:
        """A missing table fails with nft's message."""
        kernel = NftKernel(
            TOOLS, Recorder({"-j list": (1, "", "Error: No such file or directory")})
        )
        with self.assertRaises(GrantError) as caught:
            kernel.elements()
        self.assertEqual(caught.exception.code, "nft")

    def test_writes(self) -> None:
        """Adds carry timeout and comment in one batch; removals use destroy."""
        recorder = Recorder({})
        kernel = NftKernel(TOOLS, recorder)
        element = Element(
            Path("vn-sbx", MAC, SANDBOX, GATEWAY, Ports("tcp", 8000, 8999)),
            "0000000a",
            "sbx-ab12",
            "host:dev",
            0,
        )
        kernel.add([element], 600, 900)
        kernel.remove([element], [element.path])
        kernel.add_route(30900, Route("vn-sbx", SANDBOX, DEV))
        self.assertEqual(
            [stdin for _, stdin in recorder.calls[:2]],
            [
                (
                    f"add element {SET_NAME} {{ {KEY} timeout 600s"
                    f' comment "0000000a sbx-ab12 host:dev {MAC}" }}\n'
                    f"destroy element {SOURCES_NAME} {{ {SOURCE_KEY} }}\n"
                    f"add element {SOURCES_NAME} {{ {SOURCE_KEY} timeout 900s }}\n"
                ),
                (
                    f"destroy element {SET_NAME} {{ {KEY} }}\n"
                    f"destroy element {SOURCES_NAME} {{ {SOURCE_KEY} }}\n"
                ),
            ],
        )
        self.assertEqual(
            recorder.calls[2][0],
            [
                "/ip",
                "rule",
                "add",
                "pref",
                "30900",
                "iif",
                "vn-sbx",
                "from",
                "172.16.2.50",
                "to",
                "172.16.1.10",
                "lookup",
                "main",
            ],
        )

    def test_flows(self) -> None:
        """Marked flows outside the path's ports stay; a vanished flow is no error."""
        recorder = Recorder(
            {"-L -f": (0, CONNTRACK, ""), "-D -f": (1, "", "0 flow entries have been deleted.")}
        )
        kernel = NftKernel(TOOLS, recorder)
        (flow,) = kernel.flows(Path("vn-sbx", MAC, SANDBOX, GATEWAY, Ports("tcp", 8000, 8999)))
        self.assertEqual((flow.sport, flow.dport), (40000, 8080))
        kernel.drop_flow(flow)
        self.assertEqual(recorder.calls[0][0][-2:], ["-m", "0x00100000/0x00f00000"])
        self.assertEqual(recorder.calls[1][0][-4:], ["--sport", "40000", "--dport", "8080"])
        failing = NftKernel(TOOLS, Recorder({"-D -f": (1, "", "Operation not permitted")}))
        with self.assertRaises(GrantError):
            failing.drop_flow(flow)

    def test_foreign_route(self) -> None:
        """A rule at the grant preference that no grant made stops the helper."""
        rules = [{"priority": 30900, "iif": "eth0", "table": "100"}]
        kernel = NftKernel(TOOLS, Recorder({"-j rule": (0, json.dumps(rules), "")}))
        with self.assertRaisesRegex(GrantError, "no grant made"):
            kernel.routes(30900)

    def test_tool_failures(self) -> None:
        """A timed-out tool and a malformed conntrack line fail with the tool's code."""
        hung = NftKernel(TOOLS, Recorder({"-j list": (124, "", "timed out after 10s")}))
        with self.assertRaisesRegex(GrantError, "timed out") as caught:
            hung.elements()
        self.assertEqual(caught.exception.code, "nft")
        garbled = NftKernel(
            TOOLS, Recorder({"-L -f": (0, "tcp src=a dst=b sport=x dport=y\n", "")})
        )
        with self.assertRaises(GrantError) as caught:
            garbled.flows(Path("vn-sbx", MAC, SANDBOX, GATEWAY, Ports("tcp", 1, 2)))
        self.assertEqual(caught.exception.code, "conntrack")

    def test_routes(self) -> None:
        """Rules at the preference parse into routes."""
        rules = [
            {
                "priority": 30900,
                "src": "172.16.2.50",
                "dst": "172.16.1.10",
                "iif": "vn-sbx",
                "table": "main",
            }
        ]
        kernel = NftKernel(TOOLS, Recorder({"-j rule": (0, json.dumps(rules), "")}))
        self.assertEqual(kernel.routes(30900), {Route("vn-sbx", SANDBOX, DEV)})
