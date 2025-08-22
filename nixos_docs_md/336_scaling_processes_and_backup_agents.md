## Scaling processes and backup agents

Scaling the number of server processes is quite easy; simply specify `services.foundationdb.serverProcesses` to be the number of FoundationDB worker processes that should be started on the machine.

FoundationDB worker processes typically require 4GB of RAM per-process at minimum for good performance, so this option is set to 1 by default since the maximum amount of RAM is unknown. You’re advised to abide by this restriction, so pick a number of processes so that each has 4GB or more.

A similar option exists in order to scale backup agent processes, `services.foundationdb.backupProcesses`. Backup agents are not as performance/RAM sensitive, so feel free to experiment with the number of available backup processes.
