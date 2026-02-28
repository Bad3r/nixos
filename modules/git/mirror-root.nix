# Creates and manages the shared /data/git mirror root.
{
  flake.nixosModules.mirror-root =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.localMirrors;
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

        # Create directory with setgid so new repos inherit group ownership
        systemd.tmpfiles.rules = [ "d ${cfg.root} 2775 root ${cfg.group} - -" ];
      };
    };
}
