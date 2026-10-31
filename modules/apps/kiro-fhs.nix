/*
  Package: kiro-fhs
  Description: Kiro agentic AI IDE, wrapped in an FHS environment.
  Homepage: https://github.com/kiro-project/kiro
  Documentation: https://github.com/kiro-project/kiro#readme
  Repository: nil

  Summary:
    * Agentic AI IDE from AWS, based on Code OSS.
*/
_:
let
  KiroFhsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."kiro-fhs".extended;
    in
    {
      options.programs.kiro-fhs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable kiro-fhs.";
        };

        package = lib.mkPackageOption pkgs "kiro-fhs" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "kiro" ];
  flake.nixosModules.apps.kiro-fhs = KiroFhsModule;
}
