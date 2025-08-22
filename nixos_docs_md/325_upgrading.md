## Upgrading

### Note

The steps below demonstrate how to upgrade from an older version to `pkgs.postgresql_13`. These instructions are also applicable to other versions.

Major PostgreSQL upgrades require a downtime and a few imperative steps to be called. This is the case because each major version has some internal changes in the databases’ state. Because of that, NixOS places the state into `/var/lib/postgresql/&lt;version&gt;` where each `version` can be obtained like this:

```programlisting
$ nix-instantiate --eval -A postgresql_13.psqlSchema
"13"
```

For an upgrade, a script like this can be used to simplify the process:

```programlisting
{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    (
      let
        # XXX specify the postgresql package you'd like to upgrade to.

        # Do not forget to list the extensions you need.

        newPostgres = pkgs.postgresql_13.withPackages (pp: [
          # pp.plv8

        ]);
        cfg = config.services.postgresql;
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" ''
        set -eux
        # XXX it's perhaps advisable to stop all services that depend on postgresql

        systemctl stop postgresql

        export NEWDATA="/var/lib/postgresql/${newPostgres.psqlSchema}"
        export NEWBIN="${newPostgres}/bin"

        export OLDDATA="${cfg.dataDir}"
        export OLDBIN="${cfg.finalPackage}/bin"

        install -d -m 0700 -o postgres -g postgres "$NEWDATA"
        cd "$NEWDATA"
        sudo -u postgres "$NEWBIN/initdb" -D "$NEWDATA" ${lib.escapeShellArgs cfg.initdbArgs}

        sudo -u postgres "$NEWBIN/pg_upgrade" \
          --old-datadir "$OLDDATA" --new-datadir "$NEWDATA" \
          --old-bindir "$OLDBIN" --new-bindir "$NEWBIN" \
          "$@"
      ''
    )
  ];
}
```

The upgrade process is:

1.  Add the above to your `configuration.nix` and rebuild. Alternatively, add that into a separate file and reference it in the `imports` list.

2.  Login as root (`sudo su -`).

3.  Run `upgrade-pg-cluster`. This will stop the old postgresql cluster, initialize a new one and migrate the old one to the new one. You may supply arguments like `--jobs 4` and `--link` to speedup the migration process. See [https://www.postgresql.org/docs/current/pgupgrade.html](https://www.postgresql.org/docs/current/pgupgrade.html) for details.

4.  Change the postgresql package in NixOS configuration to the one you were upgrading to via [`services.postgresql.package`](options.html#opt-services.postgresql.package). Rebuild NixOS. This should start the new postgres version using the upgraded data directory and all services you stopped during the upgrade.

5.  After the upgrade it’s advisable to analyze the new cluster:
    - For PostgreSQL ≥ 14, use the `vacuumdb` command printed by the upgrades script.

    - For PostgreSQL \< 14, run (as `su -l postgres` in the [`services.postgresql.dataDir`](options.html#opt-services.postgresql.dataDir), in this example `/var/lib/postgresql/13`):

      ```programlisting
      $ ./analyze_new_cluster.sh
      ```

    ### Warning

    The next step removes the old state-directory!

    ```programlisting
    $ ./delete_old_cluster.sh
    ```
