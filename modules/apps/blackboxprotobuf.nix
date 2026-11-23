/*
  Package: python3Packages.bbpb
  Description: Protobuf decoder and encoder that works without type definitions.
  Homepage: https://github.com/nccgroup/blackboxprotobuf
  Documentation: https://github.com/nccgroup/blackboxprotobuf/blob/master/lib/CLI.md
  Repository: https://github.com/nccgroup/blackboxprotobuf

  Summary:
    * Decodes Protobuf messages to JSON with an inferred type definition, and re-encodes edited JSON.
    * Provides the `bbpb` command.
*/
_:
let
  BlackboxprotobufModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.blackboxprotobuf.extended;
    in
    {
      options.programs.blackboxprotobuf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Blackbox Protobuf.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "bbpb" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.blackboxprotobuf = BlackboxprotobufModule;
}
