{
  flake.nixosModules.git."ghq-root" =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.git.ghqRoot;
    in
    {
      options.git.ghqRoot = {
        enable = lib.mkEnableOption "provision of a shared ghq repository root";

        root = lib.mkOption {
          type = lib.types.str;
          default = "/git";
          example = "/srv/git";
          description = ''
            Absolute path where ghq should mirror repositories. The directory
            is created with the configured ownership and permissions via
            systemd-tmpfiles.
          '';
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "users";
          description = "POSIX group that owns the shared ghq root.";
        };

        mode = lib.mkOption {
          type = lib.types.str;
          default = "2775";
          description = ''
            Octal mode applied to the ghq root. The default keeps the setgid
            bit so new clones inherit the group and stay group-writable.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Ensure ghq is available system-wide for every user.
        environment.systemPackages = lib.mkAfter [
          pkgs.ghq
          pkgs.git
          pkgs.coreutils
        ];

        # Export GHQ_ROOT so interactive shells use the shared location by default.
        environment.sessionVariables.GHQ_ROOT = lib.mkDefault cfg.root;

        # Create and maintain the shared root with predictable ownership.
        systemd.tmpfiles.rules = lib.mkAfter [
          "d ${cfg.root} ${cfg.mode} root ${cfg.group} - -"
        ];
      };
    };
}
