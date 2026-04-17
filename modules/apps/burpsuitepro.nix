/*
  Package: burpsuitepro
  Description: Integrated web security testing platform from PortSwigger for intercepting, scanning, and manipulating HTTP/S traffic.
  Homepage: https://portswigger.net/
  Documentation: https://portswigger.net/burp/documentation
  Repository: https://gitlab.com/_VX3r/burpsuite-pro-flake

  Summary:
    * Provides the packaged Burp Suite Professional desktop client from the `burpsuite-pro-flake` input.
    * Registers the overlay that exposes `pkgs.burpsuitepro` so downstream modules (`burpsuite-loader`, devshell, ad-hoc overrides) share a single derivation.

  Options:
    burpsuitepro: Launch Burp Suite Professional with the packaged runtime.
    BURP_JVM_ARGS=...: Override JVM sizing for large engagements.
    JAVA_TOOL_OPTIONS=...: Pass additional Java flags to the packaged launcher.

  Example Usage:
    * `burpsuitepro` -- Start the Professional edition and configure the browser proxy to intercept traffic.
    * `BURP_JVM_ARGS="-Xmx8G" burpsuitepro` -- Allocate a larger heap for sustained scans.
    * Install the companion `burpsuite-loader` module when license-loader bootstrap is needed outside the devshell.

  Notes:
    * Package sourced from `inputs."burpsuite-pro-flake"`; the overlay below is the single place that ties the flake input to `pkgs.burpsuitepro`.
*/
{ inputs, ... }:
let
  packageFor = system: inputs."burpsuite-pro-flake".packages.${system}.burpsuitepro;

  BurpsuiteProModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.burpsuitepro.extended;
    in
    {
      options.programs.burpsuitepro.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Burp Suite Professional.";
        };

        package = lib.mkPackageOption pkgs "burpsuitepro" { };
      };

      config = {
        # Overlay is unconditional so `pkgs.burpsuitepro` resolves even when the
        # module is not enabled — sibling modules (burpsuite-loader, devshell
        # consumers, local overrides) rely on that attribute being present.
        nixpkgs.overlays = [
          (_final: prev: {
            burpsuitepro = packageFor prev.stdenv.hostPlatform.system;
          })
        ];

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "burpsuitepro" ];
  flake.nixosModules.apps.burpsuitepro = BurpsuiteProModule;
}
