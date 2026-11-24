/*
  Package: upx
  Description: Executable packer.
  Homepage: https://upx.github.io/
  Documentation: https://github.com/upx/upx/blob/devel/doc/upx-doc.txt
  Repository: https://github.com/upx/upx

  Summary:
    * Compresses and decompresses ELF, PE, and Mach-O executables.
    * Unpacks UPX-packed samples with `upx -d`.
*/
_:
let
  UpxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.upx.extended;
    in
    {
      options.programs.upx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable UPX.";
        };

        package = lib.mkPackageOption pkgs "upx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.upx = UpxModule;
}
