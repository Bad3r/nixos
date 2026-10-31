/*
  Package: lazydocker
  Description: Simple terminal UI for both Docker and Docker Compose.
  Homepage: https://github.com/jesseduffield/lazydocker
  Documentation: https://github.com/jesseduffield/lazydocker/blob/master/README.md
  Repository: https://github.com/jesseduffield/lazydocker

  Summary:
    * Provides a unified TUI for monitoring and managing Docker containers, services, images, volumes, and networks.
    * Displays real-time resource metrics (CPU, memory, network I/O, block I/O) as ASCII graphs with vim-like navigation.

  Options:
    -f: Specify Docker Compose file(s) to use.
    -c: Specify a custom config directory path.
    -d: Enable debug logging.
*/
_:
let
  LazydockerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lazydocker.extended;
    in
    {
      options.programs.lazydocker.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lazydocker.";
        };

        package = lib.mkPackageOption pkgs "lazydocker" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # The Docker API engine behind /run/docker.sock.
        programs.podman.extended.enable = lib.mkOverride 1050 true;
      };
    };
in
{
  flake.nixosModules.apps.lazydocker = LazydockerModule;
}
