# Regression coverage for storage-dependent writers disabled on system76.
#
# The dedicated /data volume moved to songbird. Keeping this check at the flake
# level makes the host exception fail during evaluation if either half of the
# common mirror feature or the R2 runtime is re-enabled accidentally.
{ config, lib, ... }:
let
  host = config.flake.nixosConfigurations.system76.config;
  ownerName = config.flake.lib.meta.owner.username;
  r2ServiceNames = [
    "r2-mount-workspace"
    "r2-bisync-workspace"
    "r2-mount-fonts"
    "r2-bisync-fonts"
    "r2-mount-docs"
    "r2-bisync-docs"
    "r2-restic-backup"
  ];
  failures =
    lib.optional host.localMirrors.enable "localMirrors.enable is enabled"
    ++
      lib.optional host.home-manager.users.${ownerName}.programs.gitMirror.enable
        "programs.gitMirror.enable is enabled"
    ++ lib.optional (host.systemd.services ? "local-mirrors-root") "local-mirrors-root.service exists"
    ++ lib.optional (
      host.home-manager.users.${ownerName}.systemd.user.services ? "git-mirror"
    ) "user git-mirror.service exists"
    ++ lib.optional (
      host.home-manager.users.${ownerName}.systemd.user.timers ? "git-mirror"
    ) "user git-mirror.timer exists"
    ++ map (name: "${name}.service exists") (
      lib.filter (name: lib.hasAttr name host.systemd.services) r2ServiceNames
    )
    ++ map (rule: "R2 data tmpfiles rule exists: ${rule}") (
      lib.filter (rule: lib.hasInfix "/data" rule) host.systemd.tmpfiles.rules
    );
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.system76-storage-safety =
        if failures != [ ] then
          throw ("system76-storage-safety: " + lib.concatStringsSep "; " failures)
        else
          pkgs.runCommandLocal "system76-storage-safety-ok" { } ''
            echo "ok: system76 has no /data-backed mirror or R2 writers" > $out
          '';
    };
}
