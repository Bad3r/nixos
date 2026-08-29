# Creates and manages the shared /data/git mirror root
# (e.g. /data/git/openai-codex, /data/git/tridactyl-tridactyl,
# or /data/git/codeberg-librewolf-settings).
{
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

      # Deepest declared mount containing the mirror root, if the host has one.
      # A host that keeps mirrors on the root filesystem yields null and is
      # provisioned unconditionally.
      enclosingMount =
        let
          contains = m: m != "/" && (m == cfg.root || lib.hasPrefix "${m}/" cfg.root);
        in
        lib.foldl' (
          best: m: if best == null || lib.stringLength m > lib.stringLength best then m else best
        ) null (lib.filter contains (lib.attrNames config.fileSystems));
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
        systemd.services.local-mirrors-root = {
          description = "Provision the local mirror root";
          wantedBy = [ "multi-user.target" ];
          after = lib.optional (enclosingMount != null) "${utils.escapeSystemdPath enclosingMount}.mount";
          unitConfig = lib.optionalAttrs (enclosingMount != null) {
            ConditionPathIsMountPoint = enclosingMount;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/install -d -m 2775 -o root -g ${cfg.group} ${cfg.root}";
          };
        };
      };
    };
}
