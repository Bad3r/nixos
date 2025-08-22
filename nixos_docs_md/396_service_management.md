## Service Management

**Table of Contents**

[Interacting with a running systemd](#sect-nixos-systemd-general)

[systemd in NixOS](#sect-nixos-systemd-nixos)

In NixOS, all system services are started and monitored using the systemd program. systemd is the “init” process of the system (i.e. PID 1), the parent of all other processes. It manages a set of so-called “units”, which can be things like system services (programs), but also mount points, swap files, devices, targets (groups of units) and more. Units can have complex dependencies; for instance, one unit can require that another unit must be successfully started before the first unit can be started. When the system boots, it starts a unit named `default.target`; the dependencies of this unit cause all system services to be started, file systems to be mounted, swap files to be activated, and so on.
