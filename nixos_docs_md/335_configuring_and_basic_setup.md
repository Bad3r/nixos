## Configuring and basic setup

To enable FoundationDB, add the following to your `configuration.nix`:

```programlisting
{
  services.foundationdb.enable = true;
  services.foundationdb.package = pkgs.foundationdb73; # FoundationDB 7.3.x

}
```

The `services.foundationdb.package` option is required, and must always be specified. Due to the fact FoundationDB network protocols and on-disk storage formats may change between (major) versions, and upgrades must be explicitly handled by the user, you must always manually specify this yourself so that the NixOS module will use the proper version. Note that minor, bugfix releases are always compatible.

After running **nixos-rebuild**, you can verify whether FoundationDB is running by executing **fdbcli** (which is added to `environment.systemPackages`):

```programlisting
$ sudo -u foundationdb fdbcli
Using cluster file `/etc/foundationdb/fdb.cluster'.

The database is available.

Welcome to the fdbcli. For help, type `help'.
fdb> status

Using cluster file `/etc/foundationdb/fdb.cluster'.

Configuration:
  Redundancy mode        - single
  Storage engine         - memory
  Coordinators           - 1

Cluster:
  FoundationDB processes - 1
  Machines               - 1
  Memory availability    - 5.4 GB per process on machine with least available
  Fault Tolerance        - 0 machines
  Server time            - 04/20/18 15:21:14

...

fdb>
```

You can also write programs using the available client libraries. For example, the following Python program can be run in order to grab the cluster status, as a quick example. (This example uses **nix-shell** shebang support to automatically supply the necessary Python modules).

```programlisting
a@link> cat fdb-status.py
#! /usr/bin/env nix-shell
#! nix-shell -i python -p python pythonPackages.foundationdb73

import fdb
import json

def main():
    fdb.api_version(520)
    db = fdb.open()

    @fdb.transactional
    def get_status(tr):
        return str(tr['\xff\xff/status/json'])

    obj = json.loads(get_status(db))
    print('FoundationDB available: %s' % obj['client']['database_status']['available'])

if __name__ == "__main__":
    main()
a@link> chmod +x fdb-status.py
a@link> ./fdb-status.py
FoundationDB available: True
a@link>
```

FoundationDB is run under the **foundationdb** user and group by default, but this may be changed in the NixOS configuration. The systemd unit **foundationdb.service** controls the **fdbmonitor** process.

By default, the NixOS module for FoundationDB creates a single SSD-storage based database for development and basic usage. This storage engine is designed for SSDs and will perform poorly on HDDs; however it can handle far more data than the alternative “memory” engine and is a better default choice for most deployments. (Note that you can change the storage backend on-the-fly for a given FoundationDB cluster using **fdbcli**.)

Furthermore, only 1 server process and 1 backup agent are started in the default configuration. See below for more on scaling to increase this.

FoundationDB stores all data for all server processes under `/var/lib/foundationdb`. You can override this using `services.foundationdb.dataDir`, e.g.

```programlisting
{ services.foundationdb.dataDir = "/data/fdb"; }
```

Similarly, logs are stored under `/var/log/foundationdb` by default, and there is a corresponding `services.foundationdb.logDir` as well.
