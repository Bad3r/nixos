/*
  Package: intelephense
  Description: PHP language server implementing LSP via the Intelephense engine.
  Homepage: https://intelephense.com/
  Documentation: https://github.com/bmewburn/vscode-intelephense/blob/master/README.md
  Repository: nil

  Summary:
    * Provides completions, diagnostics, go-to-definition, and find-references for PHP projects.
*/
_:
let
  IntelephenseModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.intelephense.extended;
    in
    {
      options.programs.intelephense.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable intelephense.";
        };

        package = lib.mkPackageOption pkgs "intelephense" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "intelephense" ];
  flake.nixosModules.apps.intelephense = IntelephenseModule;
}
