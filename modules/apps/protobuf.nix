/*
  Package: protobuf
  Description: Protocol Buffers compiler and runtime libraries.
  Homepage: https://protobuf.dev/
  Documentation: https://protobuf.dev/programming-guides/
  Repository: https://github.com/protocolbuffers/protobuf

  Summary:
    * Provides the `protoc` compiler, which generates code from `.proto` schemas.
    * Decodes raw protobuf messages with `protoc --decode_raw`.
*/
_:
let
  ProtobufModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.protobuf.extended;
    in
    {
      options.programs.protobuf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Protocol Buffers compiler.";
        };

        package = lib.mkPackageOption pkgs "protobuf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.protobuf = ProtobufModule;
}
