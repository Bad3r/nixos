/*
  Package: podman-desktop
  Description: Graphical tool for developing on containers and Kubernetes.
  Homepage: https://podman-desktop.io/
  Documentation: https://podman-desktop.io/docs/intro
  Repository: https://github.com/podman-desktop/podman-desktop

  Summary:
    * Manages containers, images, pods, volumes, and Kubernetes resources from a desktop UI.
    * Connects to the owner's rootless Podman API socket that the podman app enables.

  Options:
    podman-desktop: Launch the desktop application.
*/
_:
let
  PodmanDesktopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."podman-desktop".extended;
    in
    {
      options.programs."podman-desktop".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Podman Desktop.";
        };

        package = lib.mkPackageOption pkgs "podman-desktop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        programs.podman.extended.enable = lib.mkOverride 1050 true;
      };
    };
in
{
  flake.nixosModules.apps."podman-desktop" = PodmanDesktopModule;
}
