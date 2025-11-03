_:
let
  MalimiteModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.malimite.extended;
    in
    {
      options.programs.malimite.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Malimite iOS and macOS decompiler.";
        };

        package = lib.mkPackageOption pkgs "malimite" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.malimite = MalimiteModule;
}
