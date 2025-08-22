## Backups and Disaster Recovery

The usual rules for doing FoundationDB backups apply on NixOS as written in the FoundationDB manual. However, one important difference is the security profile for NixOS: by default, the **foundationdb** systemd unit uses _Linux namespaces_ to restrict write access to the system, except for the log directory, data directory, and the **/etc/foundationdb/** directory. This is enforced by default and cannot be disabled.

However, a side effect of this is that the **fdbbackup** command doesn’t work properly for local filesystem backups: FoundationDB uses a server process alongside the database processes to perform backups and copy the backups to the filesystem. As a result, this process is put under the restricted namespaces above: the backup process can only write to a limited number of paths.

In order to allow flexible backup locations on local disks, the FoundationDB NixOS module supports a `services.foundationdb.extraReadWritePaths` option. This option takes a list of paths, and adds them to the systemd unit, allowing the processes inside the service to write (and read) the specified directories.

For example, to create backups in **/opt/fdb-backups**, first set up the paths in the module options:

```programlisting
{ services.foundationdb.extraReadWritePaths = [ "/opt/fdb-backups" ]; }
```

Restart the FoundationDB service, and it will now be able to write to this directory (even if it does not yet exist.) Note: this path _must_ exist before restarting the unit. Otherwise, systemd will not include it in the private FoundationDB namespace (and it will not add it dynamically at runtime).

You can now perform a backup:

```programlisting
$ sudo -u foundationdb fdbbackup start  -t default -d file:///opt/fdb-backups
$ sudo -u foundationdb fdbbackup status -t default
```
