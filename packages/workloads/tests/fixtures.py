# Copyright (c) 2026 Bad3r
"""A grant policy shaped like the one modules/workloads/sharing/grants.nix writes."""

import copy
import json

from workloads.grants import Policy, Record

POLICY: Record = {
    "maxConcurrent": 2,
    "routePreference": 30900,
    "rules": [
        {"from": ["sbx-*"], "to": ["host:dev", "host:api", "guest:dev:8080"], "maxTtl": 7200},
        {"from": ["guest:dev"], "to": ["host:dev"], "maxTtl": 86400},
    ],
    "networks": {
        "sbx": {
            "bridge": "vn-sbx",
            "subnet": "172.16.2.0/24",
            "gateway": "172.16.2.1",
            "isolatePeers": True,
            "sandboxes": True,
            "leases": "/leases/vn-sbx.status",
        },
        "desktop": {
            "bridge": "vn-desktop",
            "subnet": "172.16.1.0/24",
            "gateway": "172.16.1.1",
            "isolatePeers": False,
            "sandboxes": False,
            "leases": None,
        },
    },
    "sources": {
        "dev": [{"network": "desktop", "address": "172.16.1.10", "mac": "52:54:00:00:01:10"}]
    },
    "targets": {
        "host": {
            "dev": {"ports": [{"from": 8000, "to": 8999, "proto": "tcp"}]},
            "api": {"ports": [{"from": 7000, "to": 7000, "proto": "tcp"}]},
        },
        "guest": {
            "dev": {
                "interfaces": [{"network": "desktop", "address": "172.16.1.10"}],
                "ports": [{"from": 8080, "to": 8080, "proto": "tcp"}],
            },
            "web": {
                "interfaces": [{"network": "desktop", "address": "172.16.1.20"}],
                "ports": [{"from": 80, "to": 80, "proto": "tcp"}],
            },
        },
    },
    "reserved": ["172.16.1.10", "172.16.2.9"],
    "shares": {
        "dev": {
            "domain": "dev",
            "kind": "nixos",
            "shares": {
                "late": {
                    "device": "/etc/workloads/shares/dev/late.xml",
                    "readOnly": False,
                    "mountPoint": "/mnt/late",
                }
            },
        },
        "win11": {
            "domain": "win11",
            "kind": "windows",
            "shares": {
                "isos": {
                    "device": "/etc/workloads/shares/win11/isos.xml",
                    "readOnly": True,
                    "mountPoint": None,
                }
            },
        },
    },
}


def policy() -> Policy:
    """A fresh parsed policy."""
    return Policy.from_json(copy.deepcopy(POLICY))


SANDBOX_MAC = "52:54:00:00:02:50"
# A lease to 2100 for the sandbox, and one long expired.
LEASES = json.dumps(
    [
        {
            "ip-address": "172.16.2.50",
            "mac-address": "52:54:00:00:02:50",
            "expiry-time": 4102444800,
        },
        {"ip-address": "172.16.2.60", "mac-address": "52:54:00:00:02:60", "expiry-time": 1},
    ]
)


def read_leases(path: str) -> str:
    """The fixture lease file, for the sandbox network only."""
    if path != "/leases/vn-sbx.status":
        raise FileNotFoundError(path)
    return LEASES


class FakeLibvirt:
    """Live virtiofs tags per domain; a detached tag lingers for `linger` polls, or forever."""

    def __init__(self, events: list[str]) -> None:
        """Every guest runs and holds nothing."""
        self.events = events
        self.states = {"dev": "running", "win11": "running"}
        self.saved_domains: set[str] = set()
        self.live: dict[str, set[str]] = {"dev": set(), "win11": set()}
        self.releasing: dict[str, tuple[str, int | None]] = {}
        self.linger: int | None = 2

    def state(self, domain: str) -> str:
        """The scripted state."""
        return self.states[domain]

    def saved(self, domain: str) -> bool:
        """Whether the domain was marked saved."""
        return domain in self.saved_domains

    def tags(self, domain: str) -> set[str]:
        """Live tags, with a releasing one until its polls run out."""
        tags = set(self.live[domain])
        if domain in self.releasing:
            tag, left = self.releasing[domain]
            if left == 0:
                del self.releasing[domain]
            else:
                tags.add(tag)
                self.releasing[domain] = (tag, None if left is None else left - 1)
        return tags

    def attach(self, domain: str, device: str) -> None:
        """Plug the device; its tag is the file's stem."""
        self.events.append(f"attach {domain} {device}")
        self.live[domain].add(device.rsplit("/", 1)[1].removesuffix(".xml"))

    def detach(self, domain: str, device: str) -> None:
        """Start releasing the device."""
        self.events.append(f"detach {domain} {device}")
        tag = device.rsplit("/", 1)[1].removesuffix(".xml")
        self.live[domain].discard(tag)
        self.releasing[domain] = (tag, self.linger)
