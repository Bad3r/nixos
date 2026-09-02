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

        # A unit rather than systemd.tmpfiles.rules: tmpfiles.d(5) creates
        # leading directories implicitly, so the rule this replaces wrote a
        # setgid group-writable tree onto the root filesystem on every boot
        # where the volume holding cfg.root was absent, which a sync then filled
        # instead of failing. A nofail mount is not ordered before
        # local-fs.target, so tmpfiles could also lose that race with the volume
        # present. Conditioned rather than required, so an absent volume leaves
        # this inactive instead of failed; recovering by hand after a late mount
        # is `systemctl start local-mirrors-root.service`. setgid so new repos
        # inherit group ownership.
        #
        # The stamp is what git-mirror tests for. It can only be written while
        # this unit's condition holds, so it lives on the volume and cannot
        # appear on a stray root of the same name. Mode carries no provenance:
        # the tmpfiles rule this replaced wrote 2775, setgid included, onto
        # exactly such a stray root.
        systemd.services.local-mirrors-root = {
          description = "Provision the local mirror root";
          wantedBy = [ "multi-user.target" ];
          inherit (mountGate) after unitConfig;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = [
              "${pkgs.coreutils}/bin/install -d -m 2775 -o root -g ${cfg.group} ${cfg.root}"
              "${pkgs.coreutils}/bin/touch ${cfg.root}/${cfg.stampName}"
            ];
          };
        };
      };
    };
}
