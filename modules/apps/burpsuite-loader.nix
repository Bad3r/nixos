/*
  Package: burpsuite-loader
  Description: Wrapper that exposes the Burp Suite Professional loader binary under a stable command name.
  Homepage: https://portswigger.net/
  Documentation: https://portswigger.net/burp/documentation
  Repository: https://gitlab.com/_VX3r/burpsuite-pro-flake

  Summary:
    * Provides a `burpsuite-loader` command backed by the `pkgs.burpsuitepro` derivation (registered by `modules/apps/burpsuitepro.nix`).
    * Keeps loader access available outside the pentesting devshell for license/bootstrap workflows.

  Options:
    burpsuite-loader: Launch the packaged loader binary for Burp Suite Professional.

  Example Usage:
    * `burpsuite-loader` -- Run the license/bootstrap loader without entering the pentesting devshell.
    * `burpsuite-loader --help` -- Pass arguments straight through to the upstream `loader` binary.

  Notes:
    * The upstream package exposes `loader`; this module wraps it as `burpsuite-loader` for PATH stability.
    * Depends on the `pkgs.burpsuitepro` overlay defined in `modules/apps/burpsuitepro.nix`.
*/
_:
let
  BurpsuiteLoaderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."burpsuite-loader".extended;
      burpsuiteLoaderPackage = pkgs.writeShellApplication {
        name = "burpsuite-loader";
        text = ''
          exec ${lib.getExe' pkgs.burpsuitepro "loader"} "$@"
        '';
      };
    in
    {
      options.programs."burpsuite-loader".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable burpsuite-loader.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = burpsuiteLoaderPackage;
          defaultText = lib.literalExpression "generated burpsuite-loader wrapper package";
          description = "The burpsuite-loader package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."burpsuite-loader" = BurpsuiteLoaderModule;
}
