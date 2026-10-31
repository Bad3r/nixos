/*
  Package: burpsuitepro
  Description: Integrated web security testing platform from PortSwigger for intercepting, scanning, and manipulating HTTP/S traffic.
  Homepage: https://portswigger.net/
  Documentation: https://portswigger.net/burp/documentation
  Repository: nil

  Notes:
    * Jython paths reset to the Nix-managed values on every launch.
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
          cfg.package;
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
        assertions = lib.optionals cfg.enable [
          {
            assertion = cfg.python.moduleDirectory == null || cfg.package ? override;
            message = "programs.burpsuitepro.extended.python.moduleDirectory requires a package with override support";
          }
        ];

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
  flake.nixosModules.apps.burpsuitepro = BurpsuiteProModule;
}
