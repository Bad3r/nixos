/*
  Package: kiro-fhs
  Description: FHS-wrapped distribution of the Kiro keyboard configuration tool.
  Homepage: https://github.com/kiro-project/kiro
  Documentation: https://github.com/kiro-project/kiro#readme
  Repository: https://github.com/kiro-project/kiro

  Summary:
    * Installs Kiro inside an FHS (Filesystem Hierarchy Standard) environment so it can run with dependencies expecting traditional Linux paths.
    * Simplifies launching Kiro alongside non-Nix components or plugins that rely on `/usr/lib` or `/usr/share` resources.

  Options:
    kiro-fhs: Provides the wrapped binary; launch via `kiro` inside an FHS container managed by the package.

  Example Usage:
    * `kiro` — Start the Kiro configuration interface from the FHS wrapper.
    * `kiro --profile custom.yaml` — Apply a specific keyboard profile using the wrapped executable.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kiro-fhs.extended;
  KiroFhsModule = {
    options.programs.kiro-fhs.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable kiro-fhs.";
      };

      package = lib.mkPackageOption pkgs "kiro-fhs" { };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "kiro-fhs" ];

      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.kiro-fhs = KiroFhsModule;
}
