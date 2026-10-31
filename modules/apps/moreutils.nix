/*
  Package: moreutils
  Description: Growing collection of the unix tools that nobody thought to write long ago when unix was young.
  Homepage: https://joeyh.name/code/moreutils/
  Repository: git://git.joeyh.name/moreutils

  Summary:
    * Provides additional Unix utilities like sponge, vidir, and vipe.
    * Enhances terminal workflows and shell scripting pipelines.
*/
_:
let
  MoreutilsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.moreutils.extended;
    in
    {
      options.programs.moreutils.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable moreutils.";
        };

        package = lib.mkPackageOption pkgs "moreutils" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.moreutils = MoreutilsModule;
}
