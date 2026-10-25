# Copyright (c) 2026 Bad3r
"""Cloud bases: hash-pinned images that `sbx base prepare` turns into bases.

A cloud image carries cloud-init and no guest agent. `prepare` boots it once
with egress, installs qemu-ga, and resets cloud-init, so every sandbox cut
from the prepared disk runs cloud-init again from its own NoCloud seed.
"""

import json
from dataclasses import dataclass

DISK = "disk.qcow2"
SEED = "seed.iso"
# The prepare boot is an ordinary sandbox under this name, so gc removes a stray one.
PREPARE_PREFIX = "prepare-"

# Runs as root over SSH on vsock in the prepare boot; `cloud-init status` exits 2
# for recoverable errors, which an image's own datasource probing can raise.
PREPARE_SCRIPT = """\
set -eu
cloud-init status --wait >/dev/null || [ "$?" -eq 2 ]
export DEBIAN_FRONTEND=noninteractive
apt-get -q update
apt-get -q -y install --no-install-recommends qemu-guest-agent
apt-get clean
rm -rf /var/lib/apt/lists/*
# Without a NIC, wait-online holds cloud-init's network stage for its whole timeout.
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
printf '[Unit]\\nConditionPathExistsGlob=/sys/class/net/en*\\n' \\
  > /etc/systemd/system/systemd-networkd-wait-online.service.d/sbx.conf
cloud-init clean --logs --machine-id --configs all
rm -f /root/.ssh/authorized_keys
fstrim -a
# A timer outlives this SSH session, which then exits before the shutdown.
systemd-run --quiet --on-active=2 systemctl poweroff
"""


@dataclass(frozen=True)
class CloudImage:
    """A cloud image's download URL and its SRI hash."""

    url: str
    hash: str


def seed_files(instance_id: str, authorized_key: str, *, network: bool) -> dict[str, str]:
    """Return the NoCloud seed that lets root in with the sandbox key and nobody else."""
    user_data = {
        # No default user: root holds the only key.
        "users": [],
        # systemd-ssh-generator runs before udev loads the vsock transport, so it
        # finds no CID and adds no socket until the generators run again.
        "bootcmd": [
            "modprobe vmw_vsock_virtio_transport",
            "systemctl daemon-reload",
            "systemctl start --no-block sshd-vsock.socket",
        ],
        "disable_root": False,
        "ssh_pwauth": False,
        "ssh_authorized_keys": [authorized_key],
    }
    files = {
        "meta-data": json.dumps({"instance-id": instance_id, "local-hostname": "sbx"}),
        # JSON is YAML, which cloud-init reads after the header line.
        "user-data": "#cloud-config\n" + json.dumps(user_data),
    }
    if not network:
        files["network-config"] = json.dumps({"network": {"config": "disabled"}})
    return files
