# Creates and manages the shared /data/git mirror root
# (e.g. /data/git/openai-codex, /data/git/tridactyl-tridactyl,
# or /data/git/codeberg-librewolf-settings).
{ lib, ... }:
let
  # Deepest declared mount containing the mirror root, if the host has one.
  # A host that keeps mirrors on the root filesystem yields null and is
  # provisioned unconditionally.
  #
  # Takes fileSystems rather than a list of mount points, so the mountPoint
  # extraction is inside the tested surface: a helper handed a ready-made list
  # of mount points would leave the attribute-name-vs-mountPoint distinction
  # untested.
  enclosingMountOf =
    root: fileSystems:
    let
      contains = m: m != "/" && (m == root || lib.hasPrefix "${m}/" root);
      # mountPoint, not the attribute name, which only defaults to it: a host
      # spelling the mount `fileSystems.data = { mountPoint = "/data"; ... }`
      # would otherwise yield null and lose both the ordering and the
      # condition, provisioning the root on /.
      mountPoints = lib.mapAttrsToList (_: fs: fs.mountPoint) fileSystems;
    in
    lib.foldl' (
      best: m: if best == null || lib.stringLength m > lib.stringLength best then m else best
    ) null (lib.filter contains mountPoints);

  # Ordering plus condition for a unit that writes under root. A null enclosing
  # mount means root sits on / itself, which stays unconditional rather than
  # gating on a mount point that never appears.
  mountGateFor =
    root: fileSystems: utils:
    let
      enclosingMount = enclosingMountOf root fileSystems;
    in
    {
      after = lib.optional (enclosingMount != null) "${utils.escapeSystemdPath enclosingMount}.mount";
      unitConfig = lib.optionalAttrs (enclosingMount != null) {
        ConditionPathIsMountPoint = enclosingMount;
      };
    };
in
{
  flake.lib.nixos = {
    _localMirrorsEnclosingMount = enclosingMountOf;
    _localMirrorsMountGate = mountGateFor;
  };

  flake.nixosModules.mirror-root =
    {
      lib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.localMirrors;
      mountGate = mountGateFor cfg.root config.fileSystems utils;
    in
    {
      options.localMirrors = {
        enable = lib.mkEnableOption "shared local mirror directory";

        root = lib.mkOption {
          type = lib.types.str;
          default = "/data/git";
          description = "Path for local repository mirrors.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "users";
          description = "Group ownership for the mirror directory.";
        };

        stampName = lib.mkOption {
          type = lib.types.str;
          default = ".local-mirrors-root";
          description = ''
            Marker this unit writes inside the root, and the only proof a
            consumer has that the root it sees is the provisioned one. Consumers
            read it through `programs.gitMirror.stampName`, which
            `modules/hosts/common/mirrors.nix` feeds from here.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ pkgs.git ];
        environment.sessionVariables.LOCAL_MIRRORS = cfg.root;

        # A oneshot unit, not tmpfiles.rules, so an absent volume leaves this
        # inactive (not failed) instead of tmpfiles creating cfg.root
        # unconditionally on the root filesystem; recover a late mount with
        # `systemctl start local-mirrors-root.service`. The stamp is what
        # git-mirror tests for, and can only be written while the mount
        # condition holds, so it cannot appear on a stray root.
        systemd.services.local-mirrors-root = {
          description = "Provision the local mirror root";
          wantedBy = [ "multi-user.target" ];
          inherit (mountGate) after unitConfig;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # systemd tokenizes these lines and expands % specifiers first,
            # so the str options go through its quoting, not the shell's.
            ExecStart = [
              (utils.escapeSystemdExecArgs [
                "${pkgs.coreutils}/bin/install"
                "-d"
                "-m"
                "2775"
                "-o"
                "root"
                "-g"
                cfg.group
                cfg.root
              ])
              (utils.escapeSystemdExecArgs [
                "${pkgs.coreutils}/bin/touch"
                "${cfg.root}/${cfg.stampName}"
              ])
            ];
          };
        };
      };
    };
}
