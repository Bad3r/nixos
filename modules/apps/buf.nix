/*
  Package: buf
  Description: Protobuf toolchain for linting, breaking-change detection, formatting, and code generation.
  Homepage: https://buf.build
  Documentation: https://buf.build/docs/
  Repository: https://github.com/bufbuild/buf

  Summary:
    * Lints and formats `.proto` files and detects breaking schema changes.
    * Generates code from Protobuf schemas and works with the Buf Schema Registry.
*/
_:
let
  BufModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.buf.extended;
    in
    {
      options.programs.buf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable buf.";
        };

        package = lib.mkPackageOption pkgs "buf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.buf = BufModule;
}
