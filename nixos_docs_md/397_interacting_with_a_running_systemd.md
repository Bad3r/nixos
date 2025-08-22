## Interacting with a running systemd

The command `systemctl` is the main way to interact with `systemd`. The following paragraphs demonstrate ways to interact with any OS running systemd as init system. NixOS is of no exception. The [next section](#sect-nixos-systemd-nixos "systemd in NixOS") explains NixOS specific things worth knowing.

Without any arguments, `systemctl` the status of active units:

```programlisting
$ systemctl
-.mount          loaded active mounted   /
swapfile.swap    loaded active active    /swapfile
sshd.service     loaded active running   SSH Daemon
graphical.target loaded active active    Graphical Interface
...
```

You can ask for detailed status information about a unit, for instance, the PostgreSQL database service:

```programlisting
$ systemctl status postgresql.service
postgresql.service - PostgreSQL Server
          Loaded: loaded (/nix/store/pn3q73mvh75gsrl8w7fdlfk3fq5qm5mw-unit/postgresql.service)
          Active: active (running) since Mon, 2013-01-07 15:55:57 CET; 9h ago
        Main PID: 2390 (postgres)
          CGroup: name=systemd:/system/postgresql.service
                  ├─2390 postgres
                  ├─2418 postgres: writer process
                  ├─2419 postgres: wal writer process
                  ├─2420 postgres: autovacuum launcher process
                  ├─2421 postgres: stats collector process
                  └─2498 postgres: zabbix zabbix [local] idle

Jan 07 15:55:55 hagbard postgres[2394]: [1-1] LOG:  database system was shut down at 2013-01-07 15:55:05 CET
Jan 07 15:55:57 hagbard postgres[2390]: [1-1] LOG:  database system is ready to accept connections
Jan 07 15:55:57 hagbard postgres[2420]: [1-1] LOG:  autovacuum launcher started
Jan 07 15:55:57 hagbard systemd[1]: Started PostgreSQL Server.
```

Note that this shows the status of the unit (active and running), all the processes belonging to the service, as well as the most recent log messages from the service.

Units can be stopped, started or restarted:

```programlisting

# systemctl stop postgresql.service

# systemctl start postgresql.service

# systemctl restart postgresql.service

```

These operations are synchronous: they wait until the service has finished starting or stopping (or has failed). Starting a unit will cause the dependencies of that unit to be started as well (if necessary).
