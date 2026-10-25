# Copyright (c) 2026 Bad3r
"""A grant policy shaped like the one modules/workloads/sharing/grants.nix writes."""

import copy

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
        },
        "desktop": {
            "bridge": "vn-desktop",
            "subnet": "172.16.1.0/24",
            "gateway": "172.16.1.1",
            "isolatePeers": False,
            "sandboxes": False,
        },
    },
    "sources": {"dev": [{"network": "desktop", "address": "172.16.1.10"}]},
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
}


def policy() -> Policy:
    """A fresh parsed policy."""
    return Policy.from_json(copy.deepcopy(POLICY))
