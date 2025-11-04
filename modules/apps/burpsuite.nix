/*
  Package: burpsuitepro
  Description: Integrated web security testing platform from PortSwigger for intercepting, scanning, and exploiting HTTP/S traffic.
  Homepage: https://portswigger.net/
  Documentation: https://portswigger.net/burp/documentation
  Repository: https://gitlab.com/_VX3r/burpsuite-pro-flake

  Summary:
    * Provides an intercepting proxy, repeater, intruder, and extensible plugins for comprehensive web pentesting.
    * Automates vulnerability scanning while offering manual tooling for exploitation and request manipulation.

  Options:
    burpsuitepro: Launch the desktop suite with the default UI inside an FHS environment.
    BURP_JVM_ARGS="-Xmx4G" burpsuitepro: Increase JVM heap for large engagements.
    JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" burpsuitepro: Run with headless-compatible settings for automation pipelines.

  Example Usage:
    * `burpsuitepro` — Start Burp Suite and configure browser proxy settings to intercept traffic.
    * `BURP_JVM_ARGS="-Xmx8G" burpsuitepro` — Allocate a larger heap for massive site crawls.
    * Add extensions from the BApp Store (e.g., Autorize, Logger++) to enhance capabilities.
*/
{ inputs, ... }:
let
  packageFor = system: inputs."burpsuite-pro-flake".packages.${system}.burpsuitepro;

  BurpsuiteModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.burpsuite.extended;
    in
    {
      options.programs.burpsuite.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Burp Suite Pro.";
        };

        package = lib.mkPackageOption pkgs "burpsuitepro" { };
      };

      config = {
        # Add overlay to make burpsuitepro available in pkgs
        # Must be unconditional so the package option can resolve
        nixpkgs.overlays = [
          (_final: prev: {
            burpsuitepro = packageFor prev.stdenv.hostPlatform.system;
          })
        ];

        nixpkgs.allowedUnfreePackages = lib.mkIf cfg.enable [ "burpsuitepro" ];

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.burpsuite = BurpsuiteModule;
}
