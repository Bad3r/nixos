## Taskserver

**Table of Contents**

[Configuration](#module-services-taskserver-configuration)

[The nixos-taskserver tool](#module-services-taskserver-nixos-taskserver-tool)

[Declarative/automatic CA management](#module-services-taskserver-declarative-ca-management)

[Manual CA management](#module-services-taskserver-manual-ca-management)

Taskserver is the server component of the now deprecated version 2 of [Taskwarrior](https://taskwarrior.org/), a free and open source todo list application.

[Taskwarrior 3.0.0 was released in March 2024](https://github.com/GothenburgBitFactory/taskwarrior/releases/tag/v3.0.0), and the sync functionality was rewritten entirely. With it, a NixOS module named [`taskchampion-sync-server`](options.html#opt-services.taskchampion-sync-server.enable) was added to Nixpkgs. Many people still want to use the old [Taskwarrior 2.6.x](https://github.com/GothenburgBitFactory/taskwarrior/releases/tag/v2.6.2), and Taskserver along with it. Hence this module and this documentation will stay here for the near future.
