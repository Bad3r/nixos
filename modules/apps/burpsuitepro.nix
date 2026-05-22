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
    python.moduleDirectory: Directory Burp uses for loading Jython modules.

  Example Usage:
    * `burpsuitepro` -- Start the Professional edition and configure the browser proxy to intercept traffic.
    * `BURP_JVM_ARGS="-Xmx8G" burpsuitepro` -- Allocate a larger heap for sustained scans.
    * Install the companion `burpsuite-loader` module when license-loader bootstrap is needed outside the devshell.

  Notes:
    * Package sourced from `inputs."burpsuite-pro-flake"`; the overlay below is the single place that ties the flake input to `pkgs.burpsuitepro`.
    * The upstream launcher writes a Jython defaults file to `$XDG_CACHE_HOME/burpsuitepro/jython-defaults.json` on every launch (containing the Nix-store `jython.jar` path and python module directory) and seeds an empty `$HOME/.BurpSuite/UserConfigPro.json` if absent.
    * Both files are passed via `--user-config-file`, defaults last, so the Nix-managed Jython paths always override GUI-edited values.
*/
{ inputs, ... }:
let
  packageFor = system: inputs."burpsuite-pro-flake".packages.${system}.burpsuitepro;

  BurpsuiteProModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.burpsuitepro.extended;
      configuredPackage =
        if cfg.python.moduleDirectory == null then
          cfg.package
        else if cfg.package ? override then
          cfg.package.override { pythonModuleDir = cfg.python.moduleDirectory; }
        else
          throw "programs.burpsuitepro.extended.python.moduleDirectory requires a package with override support";
    in
    {
      options.programs.burpsuitepro.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Burp Suite Professional.";
        };

        package = lib.mkPackageOption pkgs "burpsuitepro" { };

        python.moduleDirectory = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/home/${metaOwner.username}/.local/share/burpsuitepro/python-modules";
          description = ''
            Directory Burp Suite Professional uses for loading Jython modules.
            The default null value keeps the package launcher default under
            XDG_DATA_HOME at runtime.
          '';
        };
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

        environment.systemPackages = lib.mkIf cfg.enable [ configuredPackage ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "burpsuitepro" ];
  flake.nixosModules.apps.burpsuitepro = BurpsuiteProModule;
}
