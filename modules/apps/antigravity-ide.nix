/*
  Package: antigravity-ide
  Description: Agentic development platform IDE from Google, built on VS Code.
  Homepage: https://antigravity.google/product/antigravity-ide
  Documentation: https://antigravity.google/docs
  Repository: nil

  Summary:
    * Provides the `antigravity-ide` desktop IDE from nixpkgs.
    * Integrates editor, terminal, browser, and autonomous coding agent workflows.
*/
_:
let
  AntigravityIdeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-ide".extended;
    in
    {
      options.programs."antigravity-ide".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-ide.";
        };

        package = lib.mkPackageOption pkgs "antigravity-ide" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "antigravity-ide" ];
  flake.nixosModules.apps."antigravity-ide" = AntigravityIdeModule;
}
