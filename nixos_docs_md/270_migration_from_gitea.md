## Migration from Gitea

### Note

Migrating is, while not strictly necessary at this point, highly recommended. Both modules and projects are likely to diverge further with each release. Which might lead to an even more involved migration.

### Warning

The last supported version of Forgejo which supports migration from Gitea is _10.0.x_. You should _NOT_ try to migrate from Gitea to Forgejo `11.x` or higher without first migrating to `10.0.x`.

See [upstream migration guide](https://forgejo.org/docs/latest/admin/gitea-migration/)

The last supported version of _Gitea_ for this migration process is _1.22_. Do _NOT_ try to directly migrate from Gitea _1.23_ or higher, as it will likely result in data loss.

See [upstream news article](https://forgejo.org/2024-12-gitea-compatibility/)

In order to migrate, the version of Forgejo needs to be pinned to `10.0.x` _before_ using the latest version. This means that nixpkgs commit [`3bb45b041e7147e2fd2daf689e26a1f970a55d65`](https://github.com/NixOS/nixpkgs/commit/3bb45b041e7147e2fd2daf689e26a1f970a55d65) or earlier should be used.

To do this, temporarily add the following to your `configuration.nix`:

```programlisting
{ pkgs, ... }:
let
  nixpkgs-forgejo-10 = import (pkgs.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "3bb45b041e7147e2fd2daf689e26a1f970a55d65";
    hash = "sha256-8JL5NI9eUcGzzbR/ARkrG81WLwndoxqI650mA/4rUGI=";
  }) { };
in
{
  services.forgejo.package = nixpkgs-forgejo-10.forgejo;
}
```

### Full-Migration

This will migrate the state directory (data), rename and chown the database and delete the gitea user.

### Note

This will also change the git remote ssh-url user from `gitea@` to `forgejo@`, when using the host’s openssh server (default) instead of the integrated one.

Instructions for PostgreSQL (default). Adapt accordingly for other databases:

```programlisting
systemctl stop gitea
mv /var/lib/gitea /var/lib/forgejo
runuser -u postgres -- psql -c '
  ALTER USER gitea RENAME TO forgejo;
  ALTER DATABASE gitea RENAME TO forgejo;
'
nixos-rebuild switch
systemctl stop forgejo
chown -R forgejo:forgejo /var/lib/forgejo
systemctl restart forgejo
```

Afterwards, the Forgejo version can be set back to a newer desired version.

### Alternatively, keeping the gitea user

Alternatively, instead of renaming the database, copying the state folder and changing the user, the forgejo module can be set up to re-use the old storage locations and database, instead of having to copy or rename them. Make sure to disable `services.gitea`, when doing this.

```programlisting
{
  services.gitea.enable = false;

  services.forgejo = {
    enable = true;
    user = "gitea";
    group = "gitea";
    stateDir = "/var/lib/gitea";
    database.name = "gitea";
    database.user = "gitea";
  };

  users.users.gitea = {
    home = "/var/lib/gitea";
    useDefaultShell = true;
    group = "gitea";
    isSystemUser = true;
  };

  users.groups.gitea = { };
}
```
