## Service hardening

The service created by the [`postgresql`-module](options.html#opt-services.postgresql.enable) uses several common hardening options from `systemd`, most notably:

- Memory pages must not be both writable and executable (this only applies to non-JIT setups).

- A system call filter (see [systemd.exec(5)](https://www.freedesktop.org/software/systemd/man/systemd.exec.html) for details on `@system-service`).

- A stricter default UMask (`0027`).

- Only sockets of type `AF_INET`/`AF_INET6`/`AF_NETLINK`/`AF_UNIX` allowed.

- Restricted filesystem access (private `/tmp`, most of the file-system hierarchy is mounted read-only, only process directories in `/proc` that are owned by the same user).
  - When using [`TABLESPACE`](https://www.postgresql.org/docs/current/manage-ag-tablespaces.html)s, make sure to add the filesystem paths to `ReadWritePaths` like this:

    ```programlisting
    {
      systemd.services.postgresql.serviceConfig.ReadWritePaths = [ "/path/to/tablespace/location" ];
    }
    ```

The NixOS module also contains necessary adjustments for extensions from `nixpkgs`, if these are enabled. If an extension or a postgresql feature from `nixpkgs` breaks with hardening, it’s considered a bug.

When using extensions that are not packaged in `nixpkgs`, hardening adjustments may become necessary.
